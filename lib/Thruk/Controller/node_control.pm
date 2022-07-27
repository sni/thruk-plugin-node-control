package Thruk::Controller::node_control;

use warnings;
use strict;

use Thruk::Action::AddDefaults ();
use Thruk::NodeControl::Utils ();

=head1 NAME

Thruk::Controller::node_control - Thruk Controller

=head1 DESCRIPTION

Thruk Controller.

=head1 METHODS

=cut

##########################################################

=head2 index

=cut
sub index {
    my ( $c ) = @_;

    return unless Thruk::Action::AddDefaults::add_defaults($c, Thruk::Constants::ADD_SAFE_DEFAULTS);

    $c->stash->{title}                 = 'Node Control';
    $c->stash->{template}              = 'node_control.tt';
    $c->stash->{infoBoxTitle}          = 'Node Control';

    my $parallel_actions = 3; # TODO: add config option
    $c->stash->{ms_parallel}         = $parallel_actions;
    $c->stash->{omd_default_version} = $c->config->{'extra_version'}; # TODO: ...

    my $action = $c->req->parameters->{'action'} || 'list';

    if($action eq 'update') {
        my $key   = $c->req->parameters->{'peer'};
        my $peer  = $c->db->get_peer_by_key($key);
        my $facts = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 1);
    }

    my $servers = [];
    # TODO: add own server
    for my $peer (@{$c->db->get_http_peers()}) {
        my $facts = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 0);
        my $server = {
            peer_key    => $peer->{'key'},
            section     => $peer->{'section'},
            gathering   => $facts->{'gathering'} || 0,
            host_name   => $facts->{'ansible_facts'}->{'ansible_fqdn'} // $peer->{'name'},
            omd_version => $facts->{'omd_version'} // '',
            omd_site    => $facts->{'omd_site'} // '',
            os_name     => $facts->{'ansible_facts'}->{'ansible_distribution'} // '',
            os_version  => $facts->{'ansible_facts'}->{'ansible_distribution_version'} // '',
            last_error  => $facts->{'last_error'} // '',
        };
        push @{$servers}, $server;
    }
    $c->stash->{data} = $servers;

    return 1;
}

##########################################################

1;
