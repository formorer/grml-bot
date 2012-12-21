package Bot::BasicBot::Pluggable::Module::Message;
{
    $Bot::BasicBot::Pluggable::Module::Message::VERSION = '0.1';
}

use base qw(Bot::BasicBot::Pluggable::Module);
use strict;
use warnings;
use AnyEvent;
use POE;
use AnyEvent::Gearman;
use JSON qw( decode_json );
use Data::Dumper;
use IRC::Formatting::HTML qw( html_to_irc );

sub init {
    my $self = shift;
    $self->config(
        {
            debug          => 1,
            gearman_server => '127.0.0.1:4730'
        }
    );
    $self->{worker} = gearman_worker $self->get('gearman_server');
}

sub connected {
    my $self = shift;
    $self->{worker}->register_function(
        message => sub { my $job = shift; $self->process_message($job) } );
}

sub help {
    return "git module that gets github messages via gearman";
}

sub process_message {
    my $self = shift;
    my $job  = shift;
    my $json = $job->workload;
    my $data = decode_json($json);

    if ( $self->get('debug') ) {
        my $filename = time();
        if ( open( my $fh, '>', "/var/spool/bot/message-$filename" ) ) {
            ;
            print $fh Dumper($json);
            close($fh);
        }
    }

    if ( !$data->{channel} ) {
        warn "No channel in payload";
        $job->complete(1);
        return;
    }

    if ( !$data->{message} ) {
        warn "No message in playload";
        $job->complete(1);
    }
    else {
        $self->tell( $data->{channel}, html_to_irc( $data->{message} ) );
        $job->complete(1);
    }
}

1;

