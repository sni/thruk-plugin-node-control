package Thruk::Controller::node_control;

use warnings;
use strict;

use Thruk::Action::AddDefaults ();
use Thruk::Backend::Manager ();
use Thruk::NodeControl::Utils ();
use Thruk::Utils::Log qw/:all/;

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

    my $config               = Thruk::NodeControl::Utils::config($c);
    my $parallel_actions     = $config->{'parallel_tasks'} // 3;
    $c->stash->{ms_parallel} = $parallel_actions;

    my $action = $c->req->parameters->{'action'} || 'list';

    if($action && $action ne 'list') {
        eval {
            return _node_action($c, $action);
        };
        if($@) {
            _warn("action %s failed: %s", $action, $@);
            return({ json => {'success' => 0, 'error' => $@} });
        }
    }
    if($action eq 'save_options') {
        Thruk::NodeControl::Utils::save_config($c, {
            'parallel_tasks'        => $c->req->parameters->{'parallel'},
            'omd_default_version'   => $c->req->parameters->{'omd_default_version'},
        });
        Thruk::Utils::set_message( $c, { style => 'success_message', msg => 'settings saved sucessfully' });
        return $c->redirect_to($c->stash->{'url_prefix'}."cgi-bin/node_control.cgi");
    }

    my $servers = [];
    for my $peer (@{Thruk::NodeControl::Utils::get_peers($c)}) {
        push @{$servers}, Thruk::NodeControl::Utils::get_server($c, $peer);
    }

    $c->stash->{omd_default_version}    = $config->{'omd_default_version'} // "omd-".$servers->[0]->{omd_version};
    $c->stash->{omd_available_versions} = $servers->[0]->{omd_available_versions};

    # sort servers by section, host_name, site
    $servers = Thruk::Backend::Manager::sort_result({}, $servers, ['section', 'host_name', 'omd_site']);

    $c->stash->{data} = $servers;

    return 1;
}

##########################################################
sub _node_action {
    my($c, $action) = @_;

    my $key  = $c->req->parameters->{'peer'};
    if(!$key) {
        return({ json => {'success' => 0, "error" => "no peer key supplied" } });
    }
    my $peer = $c->db->get_peer_by_key($key);
    if(!$peer) {
        return({ json => {'success' => 0, "error" => "no such peer found by key" } });
    }

    if($action eq 'update') {
        return unless Thruk::Utils::check_csrf($c);
        my $facts = Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 1);
        return({ json => {'success' => 1} });
    }

    if($action eq 'facts') {
        $c->stash->{s}          = Thruk::NodeControl::Utils::get_server($c, $peer);
        $c->stash->{template}   = 'node_control_facts.tt';
        $c->stash->{modal}      = $c->req->parameters->{'modal'} // 0;
        $c->stash->{no_tt_trim} = 1;
        return 1;
    }

    if($action eq 'omd_status') {
        $c->stash->{s}          = Thruk::NodeControl::Utils::get_server($c, $peer);
        $c->stash->{template}   = 'node_control_omd_status.tt';
        $c->stash->{modal}      = $c->req->parameters->{'modal'} // 0;
        return 1;
    }

    if($action eq 'omd_stop') {
        return unless Thruk::Utils::check_csrf($c);
        my $service = $c->req->parameters->{'service'};
        Thruk::NodeControl::Utils::omd_service($c, $peer, $service, "stop");
        Thruk::NodeControl::Utils::update_runtime_data($c, $peer, 1);
        return({ json => {'success' => 1} });
    }

    if($action eq 'omd_start') {
        return unless Thruk::Utils::check_csrf($c);
        my $service = $c->req->parameters->{'service'};
        Thruk::NodeControl::Utils::omd_service($c, $peer, $service, "start");
        Thruk::NodeControl::Utils::update_runtime_data($c, $peer, 1);
        return({ json => {'success' => 1} });
    }

    if($action eq 'omd_restart') {
        return unless Thruk::Utils::check_csrf($c);
        my $service = $c->req->parameters->{'service'};
        Thruk::NodeControl::Utils::omd_service($c, $peer, $service, "restart");
        Thruk::NodeControl::Utils::update_runtime_data($c, $peer, 1);
        return({ json => {'success' => 1} });
    }

    if($action eq 'cleanup') {
        return unless Thruk::Utils::check_csrf($c);
        # TODO: ...
        Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 1);
        return({ json => {'success' => 1} });
    }

    if($action eq 'omd_install') {
        return unless Thruk::Utils::check_csrf($c);
        # TODO: ...
        Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 1);
        return({ json => {'success' => 1} });
    }

    if($action eq 'omd_update') {
        return unless Thruk::Utils::check_csrf($c);
        # TODO: ...
        Thruk::NodeControl::Utils::ansible_get_facts($c, $peer, 1);
        return({ json => {'success' => 1} });
    }

    return;
}

##########################################################

1;
