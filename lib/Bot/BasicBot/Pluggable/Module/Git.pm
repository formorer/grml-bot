package Bot::BasicBot::Pluggable::Module::Git;
{
    $Bot::BasicBot::Pluggable::Module::Git::VERSION = '0.1';
}

use base qw(Bot::BasicBot::Pluggable::Module);
use strict;
use warnings;
use AnyEvent;
use POE;
use AnyEvent::Gearman;
use JSON qw( decode_json );
use Data::Dumper;
use Date::Parse;
use WWW::Shorten::Googl;
use IRC::Formatting::HTML qw( html_to_irc );

sub init {
    my $self = shift;
    $self->config(
        {
            max_commits    => 3,
            debug          => 0,
            channel        => '#grml-test',
            gearman_server => '127.0.0.1:4730'
        }
    );
    $self->{worker} = gearman_worker $self->get('gearman_server');
}

sub connected {
    my $self = shift;
    $self->{worker}->register_function(
        githubmessage => sub { my $job = shift; $self->process_json($job) } );
}

sub help {
    return "git module that gets github messages via gearman";
}

sub process_json {
    my $self = shift;
    my $job  = shift;
    my $json = $job->workload;
    my $data = decode_json($json);

    if ( $self->get('debug') ) {
        my $filename = time();
        if ( open( my $fh, '>', "/var/spool/bot/$filename" ) ) {
            ;
            print $fh Dumper($json);
            close($fh);
        }
    }

    my @commits =
      sort { str2time( $b->{timestamp} ) <=> str2time( $a->{timestamp} ) }
      @{ $data->{commits} }
      if $data->{commits};
    $self->format_pullrequest($data)
      if $data->{action} && $data->{pull_request};
    $self->format_issue($data) if $data->{action} && $data->{issue};
    $self->format_commits( \@commits, $data ) if @commits;
    $self->format_tag($data) if $data->{ref} =~ /\/tags\//;
    $job->complete(1);
}

sub format_issue {
    my $self    = shift;
    my $data    = shift;
    my $message = sprintf '<b>%s</b> %s %s issue #%s - %s',
      $data->{repository}->{name},
      $data->{sender}->{login},
      $data->{action},
      $data->{issue}->{number},
      $data->{issue}->{title};
    $self->tell( $self->get('channel'), html_to_irc($message) );
}

sub format_pullrequest {
    my $self = shift;
    my $data = shift;
    my $message =
      sprintf '<b>%s</b> %s %s pull-request #%s - %s (+%s,-%s) - %s',
      $data->{repository}->{name},
      $data->{sender}->{login},
      $data->{action},
      $data->{pull_request}->{number},
      $data->{pull_request}->{title},
      $data->{pull_request}->{additions},
      $data->{pull_request}->{deletions},
      $data->{pull_request}->{patch_url};
    $self->tell( $self->get('channel'), html_to_irc($message) );
}

sub format_tag {
    my $self       = shift;
    my $data       = shift;
    my @components = split( '/', $data->{ref} );
    my $tag        = splice( @components, -1, 1 );
    my $message    = sprintf "%s pushed a new tag: %s (%s)",
      $data->{pusher}->{name},
      $tag,
      substr( $data->{after}, 0, 7 );
    $self->tell( $self->get('channel'), $message );
}

sub format_commits {
    my $self    = shift;
    my $commits = shift;
    my $data    = shift;

    my @commits_to_show = splice( @{$commits}, 0, $self->get('max_commits') );

#${author}  ${reponame}:${branch} * ${short commit id}: ${first line of commit message} - ${url to commit on github}

    my @components = split( '/', $data->{ref} );
    my $branch = splice( @components, -1, 1 );
    foreach my $commit (@commits_to_show) {
        my $shorturl      = makeashorterlink( $commit->{url} );
        my @commitmessage = split( "\n", $commit->{message} );
        my $message       = sprintf "%s <b>%s</b>:%s * %s: %s - %s",
          $commit->{author}->{name},
          $data->{repository}->{name},
          $branch,
          substr( $commit->{id}, 0, 7 ),
          $commitmessage[0],
          $shorturl ? $shorturl : $commit->{url};
        $self->tell( $self->get('channel'), html_to_irc($message) );
    }

    if ( @{$commits} ) {
        my $message =
          sprintf "%s other commits suppressed. See %s for all commits",
          scalar( @{$commits} ),
          $data->{compare};
        $self->tell( $self->get('channel'), $message );
    }
}

1;
