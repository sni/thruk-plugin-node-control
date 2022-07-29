package Thruk::NodeControl::Utils;

use warnings;
use strict;
use Cpanel::JSON::XS ();

use Thruk::Constants qw/:peer_states/;
use Thruk::Utils::IO ();
use Thruk::Utils::Log qw/:all/;

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

=head2 get_server

  get_server($c)

return server details

=cut
sub get_server {
    my($c, $peer) = @_;
    my $facts = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 0);
    $facts->{'last_error'} =~ s/\s+at\s+.*HTTP\.pm\s+line\s+\d+\.//gmx if $facts->{'last_error'};
    my $server = {
        peer_key                => $peer->{'key'},
        section                 => $peer->{'section'},
        gathering               => $facts->{'gathering'} || 0,
        cleaning                => $facts->{'cleaning'} || 0,
        installing              => $facts->{'installing'} || 0,
        updating                => $facts->{'updating'} || 0,
        host_name               => $facts->{'ansible_facts'}->{'ansible_fqdn'} // $peer->{'name'},
        omd_version             => $facts->{'omd_version'} // '',
        omd_versions            => $facts->{'omd_versions'} // [],
        omd_cleanable           => $facts->{'omd_cleanable'} // [],
        omd_site                => $facts->{'omd_site'} // '',
        omd_status              => $facts->{'omd_status'} // {},
        os_name                 => $facts->{'ansible_facts'}->{'ansible_distribution'} // '',
        os_version              => $facts->{'ansible_facts'}->{'ansible_distribution_version'} // '',
        machine_type            => _machine_type($facts) // '',
        cpu_cores               => $facts->{'ansible_facts'}->{'ansible_processor_vcpus'} // '',
        cpu_perc                => $facts->{'omd_cpu_perc'} // '',
        memtotal                => $facts->{'ansible_facts'}->{'ansible_memtotal_mb'} // '',
        memfree                 => $facts->{'ansible_facts'}->{'ansible_memory_mb'}->{'nocache'}->{'free'} // '',
        omd_disk_total          => $facts->{'omd_disk_total'} // '',
        omd_disk_free           => $facts->{'omd_disk_free'} // '',
        omd_available_versions  => $facts->{'omd_packages_available'} // [],
        last_error              => $facts->{'last_error'} // '',
        facts                   => $facts || {},
    };
    return($server);
}

##########################################################

=head2 ansible_get_facts

  ansible_get_facts($c, $peer)

return ansible gather facts

=cut
sub ansible_get_facts {
    my($c, $peer, $refresh) = @_;
    Thruk::Utils::IO::mkdir_r($c->config->{'var_path'}.'/node_control');
    my $file = $c->config->{'var_path'}.'/node_control/'.$peer->{'key'}.'.json';
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

=head2 update_runtime_data

  update_runtime_data($c, $peer)

update runtime data and return facts

=cut
sub update_runtime_data {
    my($c, $peer, $skip_cpu) = @_;

    my $f = ansible_get_facts($c, $peer, 0);
    return($f) unless defined $f->{'ansible_facts'}; # update only if we at least fetched facts once

    Thruk::Utils::IO::mkdir_r($c->config->{'var_path'}.'/node_control');
    my $file = $c->config->{'var_path'}.'/node_control/'.$peer->{'key'}.'.json';
    Thruk::Utils::IO::json_lock_patch($file, { 'gathering' => $$ }, { pretty => 1, allow_empty => 1 });
    my $runtime = {};
    eval {
        $runtime = _runtime_data($c, $peer, $skip_cpu);
    };
    my $err = $@;
    if($err) {
        $f = Thruk::Utils::IO::json_lock_patch($file, { 'gathering' => 0, 'last_error' => $err }, { pretty => 1, allow_empty => 1 });
    } else {
        $f = Thruk::Utils::IO::json_lock_patch($file, { 'gathering' => 0, 'last_error' => '', %{$runtime}  }, { pretty => 1, allow_empty => 1 });
    }
    return($f);
}

##########################################################
sub _ansible_get_facts {
    my($c, $peer, $refresh) = @_;
    my $file = $c->config->{'var_path'}.'/node_control/'.$peer->{'key'}.'.json';
    if(!$refresh && -e $file) {
        return(Thruk::Utils::IO::json_lock_retrieve($file));
    }
    if(defined $refresh && !$refresh) {
        return;
    }

    Thruk::Utils::IO::json_lock_patch($file, { 'gathering' => $$ }, { pretty => 1, allow_empty => 1 });

    # available subsets are listed here:
    # https://docs.ansible.com/ansible/latest/collections/ansible/builtin/setup_module.html#parameter-gather_subset
    # however, older ansible release don't support all of them and bail out
    my $f       = _ansible_adhoc_cmd($c, $peer, "-m setup -a 'gather_subset=hardware,virtual gather_timeout=30'");
    my $runtime = _runtime_data($c, $peer);
    my $pkgs    = _ansible_available_packages($c, $peer, $f);

    # merge hashes
    $f = {%{$f//{}}, %{$runtime//{}}, %{$pkgs//{}}};

    Thruk::Utils::IO::json_lock_store($file, $f, { pretty => 1 });
    return($f);
}

##########################################################
sub _runtime_data {
    my($c, $peer, $skip_cpu) = @_;
    my $runtime = {};
    my(undef, $omd_version) = _remote_cmd($c, $peer, ['omd version -b']);
    chomp($omd_version);
    $runtime->{'omd_version'} = $omd_version;

    my(undef, $omd_status) = _remote_cmd($c, $peer, ['omd status -b']);
    my %services = ($omd_status =~ m/^(\S+?)\s+(\d+)/gmx);
    $runtime->{'omd_status'} = \%services;

    my(undef, $omd_site) = _remote_cmd($c, $peer, ['id -un']);
    chomp($omd_site);
    $runtime->{'omd_site'} = $omd_site;

    my(undef, $omd_disk) = _remote_cmd($c, $peer, ['df -k version/.']);
    if($omd_disk =~ m/^.*\s+(\d+)\s+(\d+)\s+(\d+)\s+/gmx) {
        $runtime->{'omd_disk_total'} = $1;
        $runtime->{'omd_disk_free'}  = $3;
    }

    if(!$skip_cpu) {
        my(undef, $omd_cpu) = _remote_cmd($c, $peer, ['top -bn2 | grep Cpu | tail -n 1']);
        if($omd_cpu =~ m/Cpu/gmx) {
            my @val = split/\s+/, $omd_cpu;
            $runtime->{'omd_cpu_perc'}  = (100-$val[7])/100;
        }
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
    @pkgs = grep(!/^(omd-labs-edition|omd-daily)/mx, @pkgs); # remove meta packages
    @pkgs = reverse sort @pkgs;
    @pkgs = map { $_ =~ s/^omd\-//gmx; $_; } @pkgs;

    # get installed omd versions
    my $installed;
    (undef, $installed) = _remote_cmd($c, $peer, ['omd versions']);
    my @inst = split/\n/, $installed;
    my $default;
    for my $i (@inst) {
        if($i =~ m/\Q(default)\E/mx) {
            $i =~ s/\s*\Q(default)\E//gmx;
            $default = $i;
        }
    }

    my %omd_sites;
    my %in_use;
    my $sites;
    (undef, $sites) = _remote_cmd($c, $peer, ['omd sites']);
    my @sites = split/\n/, $sites;
    for my $s (@sites) {
        my($name, $version, $comment) = split/\s+/, $s;
        $omd_sites{$name} = $version;
        $in_use{$version} = 1;
    }
    $in_use{$default} = 1;

    my @cleanable;
    for my $v (@inst) {
        next if $in_use{$v};
        push @cleanable, $v;
    }

    return({ omd_packages_available => \@pkgs, omd_versions => \@inst, omd_cleanable => \@cleanable, omd_sites => \%omd_sites });
}

##########################################################

=head2 omd_install

  omd_install($c, $peer, $version)

installs given version on peer

=cut
sub omd_install {
    my($c, $peer, $version) = @_;

    my $facts = _ansible_get_facts($c, $peer, 0);
    if(!$facts->{'ansible_facts'}->{'ansible_pkg_mgr'}) {
        die("no package manager");
    }

    $version = "omd-".$version;

    return(1, "install already running") if $facts->{'installing'};

    my $file = $c->config->{'var_path'}.'/node_control/'.$peer->{'key'}.'.json';
    my $f = Thruk::Utils::IO::json_lock_patch($file, { 'installing' => 1, 'last_error' => '' }, { pretty => 1, allow_empty => 1 });

    my($rc, $out);
    eval {
        if($facts->{'ansible_facts'}->{'ansible_pkg_mgr'} eq 'yum') {
            ($rc, $out) = _remote_cmd($c, $peer, ['sudo -n yum install -y '.$version]);
        } elsif($facts->{'ansible_facts'}->{'ansible_pkg_mgr'} eq 'dnf') {
            ($rc, $out) = _remote_cmd($c, $peer, ['sudo -n dnf install -y '.$version]);
        } elsif($facts->{'ansible_facts'}->{'ansible_pkg_mgr'} eq 'apt') {
            ($rc, $out) = _remote_cmd($c, $peer, ['sudo -n apt-get install -y '.$version]);
        } else {
            die("unknown package manager: ".$facts->{'ansible_facts'}->{'ansible_pkg_mgr'}//'none');
        }

        ansible_get_facts($c, $peer, 1);

        die($out) unless $rc == 0;
    };
    if($@) {
        $f = Thruk::Utils::IO::json_lock_patch($file, { 'installing' => 0, 'last_error' => $@ }, { pretty => 1, allow_empty => 1 });
    }

    return($rc, $out);
}

##########################################################

=head2 omd_update

  omd_update($c, $peer, $version)

update site to given version on peer

=cut
sub omd_update {
    my($c, $peer, $version) = @_;

    # TODO: ...

    return;
}

##########################################################

=head2 omd_cleanup

  omd_cleanup($c, $peer)

runs omd cleanup on peer

=cut
sub omd_cleanup {
    my($c, $peer) = @_;
    my($rc, $out) = _remote_cmd($c, $peer, ['sudo -n omd cleanup']);
    return($rc, $out);
}

##########################################################
sub _remote_cmd {
    my($c, $peer, $cmd) = @_;
    my($rc, $out);
    eval {
        ($rc, $out) = $peer->cmd($c, $cmd);
    };
    my $err = $@;
    if($err) {
        _warn("remote cmd failed: %s", $err);
        # fallback to ssh if possible
        my $facts     = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 0);
        my $host_name = $facts->{'ansible_facts'}->{'ansible_fqdn'};
        if($host_name) {
            ($rc, $out) = Thruk::Utils::IO::cmd($c, "ansible all -i $host_name, -m shell -a \"".join(" ", @{$cmd})."\"");
            if($rc != 0) {
                die($out);
            }
        } else {
            die($err);
        }
    }
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

=head2 omd_service

  omd_service($c, $peer, $service, $cmd)

start/stop omd services

=cut
sub omd_service {
    my($c, $peer, $service, $cmd) = @_;
    my($rc, $out);
    eval {
        ($rc, $out) = _remote_cmd($c, $peer, ['omd '.$cmd.' '.$service]);
    };
    if($@) {
        _warn("omd cmd failed: %s", $out);
    }
    return;
}

##########################################################

=head2 config

  config($c)

return node control config

=cut
sub config {
    my($c) = @_;
    my $file = $c->config->{'var_path'}.'/node_control/_conf.json';
    my $var;
    if(-e $file) {
        $var = Thruk::Utils::IO::json_lock_retrieve($file);
    }
    # merge var into config
    my $conf = {%{$c->config->{'Thruk::Plugin::NodeControl'}//{}}, %{$var//{}}};
    return($conf);
}

##########################################################

=head2 save_config

  save_config($c)

save config to disk

=cut
sub save_config {
    my($c, $newconf) = @_;
    my $conf = {%{config($c)}, %{$newconf//{}}};
    my $file = $c->config->{'var_path'}.'/node_control/_conf.json';
    Thruk::Utils::IO::json_lock_store($file, $conf);
    return;
}

##########################################################

sub _machine_type {
    my($facts) = @_;
    if($facts->{'ansible_facts'}->{'ansible_virtualization_role'} && $facts->{'ansible_facts'}->{'ansible_virtualization_role'} eq 'guest') {
        return($facts->{'ansible_facts'}->{'ansible_virtualization_type'});
    }
    return;
}

##########################################################

1;
