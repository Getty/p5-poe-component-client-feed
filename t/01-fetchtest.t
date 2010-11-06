#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Cwd;
use File::Spec::Functions;

my $path = catdir( getcwd(), 't', 'data' );
my $port = $ENV{POE_COMPONENT_CLIENT_FEED_TEST_PORT} ? $ENV{POE_COMPONENT_CLIENT_FEED_TEST_PORT} : 63221;

SKIP: {
	eval { require POE::Component::Server::HTTP };

	skip "You need POE::Component::Server::HTTP installed", 1 if $@;

	my $atom_cnt = 0;
	my $rss_cnt = 0;

	{
		package Test::PoCoClFe::Example;
		use MooseX::POE;
		use POE::Component::Client::Feed;
		use POE::Component::Server::HTTP;
		use File::Spec::Functions;
		use Slurp;

		event 'feed_received' => sub {
			my ( $self, @args ) = @_[ OBJECT, ARG0..$#_ ];
			my $http_request = $args[0];
			my $xml_feed = $args[1];
			my $tag = $args[2];
			my $cnt = 0;
			for my $entry ($xml_feed->entries) {
				$cnt++;
			}
			if ($tag eq 'atom') {
				::isa_ok($http_request, "HTTP::Request", "First arg is HTTP::Request on receive");
				::isa_ok($xml_feed, "XML::Feed::Format::Atom", "Second arg is XML::Feed::Format::Atom on receive");
				$atom_cnt = $cnt;
				$self->client->yield('request','http://localhost:'.$port.'/rss','feed_received','rss');
			} elsif ($tag eq 'rss') {
				::isa_ok($http_request, "HTTP::Request", "First arg is HTTP::Request on receive");
				::isa_ok($xml_feed, "XML::Feed::Format::RSS", "Second arg is XML::Feed::Format::RSS on receive");
				$rss_cnt = $cnt;
				POE::Kernel->stop;
			}
		};
		
		has 'server' => (
			is => 'rw',
		);

		has 'client' => (
			is => 'rw',
		);

		sub START {
			my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];
			$self->server(POE::Component::Server::HTTP->new(
				Port => $port,
				ContentHandler => {
					'/atom' => sub { 
						my ($request, $response) = @_;
						$response->code(RC_OK);
						my $content = slurp( catfile( $path, "atom.xml" ) );
						$response->content( $content );
						$response->content_type('application/xhtml+xml');
						return RC_OK;
					},
					'/rss' => sub { 
						my ($request, $response) = @_;
						$response->code(RC_OK);
						my $content = slurp( catfile( $path, "rss.xml" ) );
						$response->content( $content );
						$response->content_type('application/xhtml+xml');
						return RC_OK;
					},
				},
				Headers => { Server => 'FeedServer' },
			));
			$self->client(POE::Component::Client::Feed->new());
			::isa_ok($self->client, "POE::Component::Client::Feed", "Getting POE::Component::Client::Feed object on new");
			$self->client->yield('request','http://localhost:'.$port.'/atom','feed_received','atom');
		}

	}

	my $test = Test::PoCoClFe::Example->new();

	POE::Kernel->run;

	is($atom_cnt,21,'Atom Feed with 21 entries is received');
	is($rss_cnt,21,'RSS Feed with 21 entries is received');
}

done_testing;
