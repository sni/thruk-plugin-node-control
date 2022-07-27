package Thruk::NodeControl::Utils;

use warnings;
use strict;

use Cpanel::JSON::XS ();

use Thruk::Constants qw/:peer_states/;
use Thruk::Controller::proxy ();

=head1 NAME

Thruk::NodeControl::Utils - Helper for the node control addon

=head1 DESCRIPTION

Helper for the node control addon

=head1 METHODS

=cut

##########################################################

=head2 update_cron_file

  update_cron_file($c)

update controlled nodes cronjobs

=cut
sub update_cron_file {
    my($c) = @_;

    # TODO: add daily cron to update facts

    return 1;
}

##########################################################

=head2 get_peers

  get_peers($c)

return list of available peers

=cut
sub get_peers {
    my($c) = @_;
    my @peers;
    for my $peer (@{$c->db->get_local_peers()}, @{$c->db->get_http_peers()}) {
        next if (defined $peer->{'disabled'} && $peer->{'disabled'} == HIDDEN_LMD_PARENT);
        push @peers, $peer;
    }
    return \@peers;
}

##########################################################

=head2 ansible_get_facts

  ansible_get_facts($c, $peer)

return ansible gather facts

=cut
sub ansible_get_facts {
    my($c, $peer, $refresh) = @_;
    Thruk::Utils::IO::mkdir_r($c->{'config'}->{'var_path'}.'/node_control');
    my $file = $c->{'config'}->{'var_path'}.'/node_control/'.$peer->{'key'}.'.json';
    my $f;
    eval {
        $f = _ansible_get_facts($c, $peer, $refresh);
    };
    if($@) {
        $f = Thruk::Utils::IO::json_lock_patch($file, { 'gathering' => 0, 'last_error' => $@ }, { pretty => 1, allow_empty => 1 });
    }
    return($f);
}

##########################################################
sub _ansible_get_facts {
    my($c, $peer, $refresh) = @_;
    my $file = $c->{'config'}->{'var_path'}.'/node_control/'.$peer->{'key'}.'.json';
    if(!$refresh && -e $file) {
        return(Thruk::Utils::IO::json_lock_retrieve($file));
    }
    if(defined $refresh && !$refresh) {
        return;
    }

    Thruk::Utils::IO::json_lock_patch($file, { 'gathering' => 1 }, { pretty => 1, allow_empty => 1 });

    my $f       = _ansible_adhoc_cmd($c, $peer, "-m setup");
    my $runtime = _runtime_data($c, $peer);
    my $pkgs    = _ansible_available_packages($c, $peer, $f);

    # merge hashes
    $f = {%{$f}, %{$runtime}, %{$pkgs}};

    Thruk::Utils::IO::json_lock_store($file, $f, { pretty => 1 });
    return($f);
}

##########################################################
sub _runtime_data {
    my($c, $peer) = @_;
    my $runtime = {};
    my(undef, $omd_version) = _remote_cmd($c, $peer, ['omd version -b']);
    chomp($omd_version);
    $runtime->{'omd_version'} = $omd_version;

    my(undef, $omd_site) = _remote_cmd($c, $peer, ['id -un']);
    chomp($omd_site);
    $runtime->{'omd_site'} = $omd_site;

    my(undef, $omd_disk) = _remote_cmd($c, $peer, ['df -k .']);
    if($omd_disk =~ m/^.*\s+(\d+)\s+(\d+)\s+(\d+)\s+/gmx) {
        $runtime->{'omd_disk_total'} = $1;
        $runtime->{'omd_disk_free'}  = $3;
    }

    my(undef, $omd_cpu) = _remote_cmd($c, $peer, ['top -bn2 | grep Cpu | tail -n 1']);
    if($omd_cpu =~ m/Cpu/gmx) {
        my @val = split/\s+/, $omd_cpu;
        $runtime->{'omd_cpu_perc'}  = (100-$val[7])/100;
    }
    return($runtime);
}

##########################################################
sub _ansible_available_packages {
    my($c, $peer, $facts) = @_;

    if(!$facts->{'ansible_facts'}->{'ansible_pkg_mgr'}) {
        die("no package manager");
    }

    my $pkgs;
    if($facts->{'ansible_facts'}->{'ansible_pkg_mgr'} eq 'yum') {
        (undef, $pkgs) = _remote_cmd($c, $peer, ['yum search omd-']);
    } elsif($facts->{'ansible_facts'}->{'ansible_pkg_mgr'} eq 'dnf') {
        (undef, $pkgs) = _remote_cmd($c, $peer, ['dnf search omd-']);
    } elsif($facts->{'ansible_facts'}->{'ansible_pkg_mgr'} eq 'apt') {
        (undef, $pkgs) = _remote_cmd($c, $peer, ['apt-cache search omd-']);
    } else {
        die("unknown package manager: ".$facts->{'ansible_facts'}->{'ansible_pkg_mgr'}//'none');
    }
    my @pkgs = ($pkgs =~ m/^(omd\-\S+?)(?:\s|\.x86_64)/gmx);
    @pkgs = grep(!/^omd-labs-edition/mx, @pkgs); # remove meta packages
    return({ omd_packages_available => \@pkgs });
}

##########################################################
sub _remote_cmd {
    my($c, $peer, $cmd) = @_;
    my($rc, $out) = $peer->cmd($c, $cmd);
    return($rc, $out);
}

##########################################################
sub _ansible_adhoc_cmd {
    my($c, $peer, $args) = @_;
    my($rc, $data) = _remote_cmd($c, $peer, ['ansible all -i localhost, -c local '.$args]);
    if($rc != 0) {
        die("ansible failed: $rc ".$data);
    }
    if($data !~ m/\Qlocalhost | SUCCESS =>\E/gmx) {
        die("ansible failed: $rc ".$data);
    }
    $data =~ s/\A.*?\Qlocalhost | SUCCESS =>\E//sgmx;
    my $jsonreader = Cpanel::JSON::XS->new->utf8;
       $jsonreader->relaxed();
    my $f;
    eval {
        $f = $jsonreader->decode($data);
    };
    if($@) {
        die("ansible failed to parse json: ".$@);
    }
    return($f);
}

##########################################################

1;
