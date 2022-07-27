package Thruk::Controller::node_control;

use warnings;
use strict;

use Thruk::Action::AddDefaults ();
use Thruk::Constants qw/:peer_states/;
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

    # no permissions at all
    return $c->detach('/error/index/8') unless $c->check_user_roles("admin");

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
    for my $peer (@{$c->db->get_http_peers()}, @{$c->db->get_local_peers()}) {
        next if (defined $peer->{'disabled'} && $peer->{'disabled'} == HIDDEN_LMD_PARENT);
        my $facts = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 0);
        my $server = {
            peer_key       => $peer->{'key'},
            section        => $peer->{'section'},
            gathering      => $facts->{'gathering'} || 0,
            host_name      => $facts->{'ansible_facts'}->{'ansible_fqdn'} // $peer->{'name'},
            omd_version    => $facts->{'omd_version'} // '',
            omd_site       => $facts->{'omd_site'} // '',
            os_name        => $facts->{'ansible_facts'}->{'ansible_distribution'} // '',
            os_version     => $facts->{'ansible_facts'}->{'ansible_distribution_version'} // '',
            cpu_cores      => $facts->{'ansible_facts'}->{'ansible_processor_cores'} // '',
            cpu_perc       => $facts->{'omd_cpu_perc'} // '',
            memtotal       => $facts->{'ansible_facts'}->{'ansible_memtotal_mb'} // '',
            memfree        => $facts->{'ansible_facts'}->{'ansible_memory_mb'}->{'nocache'}->{'free'} // '',
            omd_disk_total => $facts->{'omd_disk_total'} // '',
            omd_disk_free  => $facts->{'omd_disk_free'} // '',
            last_error     => $facts->{'last_error'} // '',
        };
        push @{$servers}, $server;
    }

    # sort servers by section, host_name, site
    $servers = Thruk::Backend::Manager::sort_result({}, $servers, ['section', 'host_name', 'omd_site']);

    $c->stash->{data} = $servers;

    return 1;
}

##########################################################

1;
