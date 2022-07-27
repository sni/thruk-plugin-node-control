package Thruk::Utils::CLI::Nodecontrol;

=head1 NAME

Thruk::Utils::CLI::Nodecontrol - NodeControl CLI module

=head1 DESCRIPTION

The nodecontrol command can start node control commands.

=head1 SYNOPSIS

  Usage: thruk [globaloptions] nc <cmd> <options>

=head1 OPTIONS

=over 4

=item B<help>

    print help and exit

=item B<cmd>

    available commands are:

    - facts <backendid|all>             update facts for given backend.

=back

=cut

use warnings;
use strict;

use Thruk::Utils::CLI ();
use Thruk::Utils::Log qw/:all/;

##############################################

=head1 METHODS

=head2 cmd

    cmd([ $options ])

=cut
sub cmd {
    my($c, $action, $commandoptions, $data, $src, $global_options) = @_;
    $c->stats->profile(begin => "_cmd_nc()");

    if(!$c->check_user_roles('authorized_for_admin')) {
        return("ERROR - authorized_for_admin role required", 1);
    }

    if(scalar @{$commandoptions} == 0) {
        return(Thruk::Utils::CLI::get_submodule_help(__PACKAGE__));
    }

    eval {
        require Thruk::NodeControl::Utils;
    };
    if($@) {
        _debug($@);
        return("node control plugin is not enabled.\n", 1);
    }

    my $mode = shift @{$commandoptions};
    my($output, $rc) = ("", 0);

    if($mode eq 'facts') {
        my $backend = shift @{$commandoptions};
        if($backend && $backend ne 'all') {
            my $peer = $c->db->get_peer_by_key($backend);
            if(!$peer) {
                _fatal("no such peer: ".$backend);
            }
            my $facts = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 1);
            if(!$facts || $facts->{'last_error'}) {
                return(sprintf("%s update failed: %s\n", $peer->{'name'}, ($facts->{'last_error'}//'unknown error')), 1);
            }
            return(sprintf("%s updated sucessfully: OK\n", $peer->{'name'}), 0);
        }
        for my $peer (@{Thruk::NodeControl::Utils::get_peers($c)}) {
            my $facts = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 1);
            if(!$facts || $facts->{'last_error'}) {
                _error("%s update failed: %s\n", $peer->{'name'}, ($facts->{'last_error'}//'unknown error'));
            }
            _info("%s updated sucessfully: OK\n", $peer->{'name'});
        }
        return("", 0);
    } else {
        return(Thruk::Utils::CLI::get_submodule_help(__PACKAGE__));
    }

    $c->stats->profile(end => "_cmd_nc()");
    return($output, $rc);
}

##############################################

=head1 EXAMPLES

Update facts for specific backend.

  %> thruk nc facts backendid

=cut

##############################################

1;
