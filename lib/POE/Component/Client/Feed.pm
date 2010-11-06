package POE::Component::Client::Feed;
# ABSTRACT: Event based feed client

use MooseX::POE;

use POE qw(
	Component::Client::HTTP
);

use HTTP::Request;
use XML::Feed;

has http_agent => (
	is => 'ro',
	isa => 'Str',
	default => sub { 'POE::Component::Client::Feed/0.0' },
);

has alias => (
	is => 'ro',
	isa => 'Str',
	required => 1,
	default => sub { 'feed' },
);

has http_alias => (
	is => 'ro',
	isa => 'Str',
	required => 1,
	lazy => 1,
	default => sub {
		my ( $self ) = @_;
		$self->http_client;
		return $self->_http_alias;
	},
);

has _http_alias => (
	is => 'ro',
	isa => 'Str',
	lazy => 1,
	default => sub {
		my ( $self ) = @_;
		return $self->alias.'_http';
	},
);

has http_timeout => (
	is => 'ro',
	isa => 'Int',
	default => sub { 30 },
);

has http_keepalive => (
	isa => 'POE::Component::Client::Keepalive',
	is => 'ro',
	lazy => 1,
	default => sub {
		POE::Component::Client::Keepalive->new(
			keep_alive    => 20, # seconds to keep connections alive
			max_open      => 100, # max concurrent connections - total
			max_per_host  => 100, # max concurrent connections - per host
			timeout       => 10, # max time (seconds) to establish a new connection
		)
	},
);

has http_followredirects => (
	is => 'ro',
	isa => 'Int',
	default => sub { 5 },
);

has http_client => (
	is => 'ro',
	lazy => 1,
	default => sub {
		my ( $self ) = @_;
		POE::Component::Client::HTTP->spawn(
			Agent     => $self->http_agent,
			Alias     => $self->_http_alias,
			Timeout   => $self->http_timeout,
			ConnectionManager => $self->http_keepalive,
			FollowRedirects => $self->http_followredirects,
		);
	},
);

use Data::Dumper;

sub START {
	my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
	$kernel->alias_set($self->alias);
}

event 'request' => sub {
	my ( $self, $sender, $feed, $response_event, $tag ) = @_[ OBJECT, SENDER, ARG0..$#_ ];
	$response_event = 'feed_received' if !$response_event;
	my $request;
	if (ref $feed) {
		$request = $feed;
	} else {
		$request = HTTP::Request->new(GET => $feed);
	}
	POE::Kernel->post(
		$self->http_alias,
		'request',
		'http_received',
		$request,
		[ $sender, $feed, $response_event, $tag ],
	);
};

event 'http_received' => sub {
	my ( $self, @args ) = @_[ OBJECT, ARG0..$#_ ];
	my $request_packet = $args[0];
	my $response_packet = $args[1];
	my $request_object  = $request_packet->[0];
	my $response_object = $response_packet->[0];
	my ( $sender, $feed, $response_event, $tag ) = @{$request_packet->[1]};
	my $content = $response_object->content;
	my $xml_feed = XML::Feed->parse(\$content);
	$xml_feed = XML::Feed->errstr if !$xml_feed;
	# i dont understand that really... need a case (Getty)
	# if (ref $response_event) {
		# $response_event->postback->($xml_feed);
	# } else {
		POE::Kernel->post( $sender, $response_event, $request_object, $xml_feed, $tag );
	# }
};

1;

__END__

=head1 SYNOPSIS

  package MyServer;
  use MooseX::POE;
  use POE::Component::Client::Feed;

  has feed_client => (
    is => 'ro',
    default => sub {
      POE::Component::Client::Feed->new();
    }
  );

  event feed_received => sub {
    my ( $self, @args ) = @_[ OBJECT, ARG0..$#_ ];
    my $http_request = $args[0];
    my $xml_feed = $args[1];
    my $tag = $args[2];
  };

  sub START {
    my ( $self ) = @_;
	$self->feed_client->yield('request','http://news.perlfoundation.org/atom.xml','feed_received','tag');
  }

=head1 DESCRIPTION

This POE Component gives you like L<POE::Component::Client::HTTP> an event based way of fetching from a feed. It is not made
for making consume a feed and only get events on new headlines, for this you can use L<POE::Component::FeedAggregator> which is
based on this module, or L<POE::Component::RSSAggregator>.

=head1 SEE ALSO

=for :list
* L<POE::Component::FeedAggregator>
* L<POE::Component::Client::HTTP>
* L<XML::Feed>
* L<MooseX::POE>
* L<POE::Component::RSSAggregator>
