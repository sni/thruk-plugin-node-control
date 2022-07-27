package Thruk::NodeControl::Utils;

use warnings;
use strict;

use Cpanel::JSON::XS ();

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
        Thruk::Utils::IO::json_lock_patch($file, { 'gathering' => 0, 'last_error' => $@ }, { pretty => 1, allow_empty => 1 });
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

    my($rc, $facts) = _remote_cmd($c, $peer, ['ansible all -i localhost, -c local -m setup']);
    if($rc != 0) {
        die("gather facts failed: $rc ".$facts);
    }
    $facts =~ s/\Qlocalhost | SUCCESS =>\E//gmx;
    my $jsonreader = Cpanel::JSON::XS->new->utf8;
       $jsonreader->relaxed();
    my $f;
    eval {
        $f = $jsonreader->decode($facts);
    };
    if($@) {
        die("gather facts failed to parse json: ".$@);
    }

    my(undef, $omd_version) = _remote_cmd($c, $peer, ['omd version -b']);
    chomp($omd_version);
    $f->{'omd_version'} = $omd_version;

    my(undef, $omd_site) = _remote_cmd($c, $peer, ['id -un']);
    chomp($omd_site);
    $f->{'omd_site'} = $omd_site;

    Thruk::Utils::IO::json_lock_store($file, $f, { pretty => 1 });
    return($f);
}

##########################################################
sub _remote_cmd {
    my($c, $peer, $cmd) = @_;
    # TODO: cmd does not end cascaded down
    my($rc, $out) = @{$peer->{'class'}->request("Thruk::Utils::IO::cmd", ['Thruk::Context', $cmd])};
    return($rc, $out);
}

##########################################################

1;
