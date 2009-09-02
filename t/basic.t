#!/usr/bin/perl

use strict;
#use warnings;

use Test::More tests => 15;

BEGIN { use_ok 'Try::Tiny' };

sub _eval {
	local $@;
	local $Test::Builder::Level = $Test::Builder::Level + 2;
	return ( scalar(eval { $_[0]->(); 1 }), $@ );
}


sub lives_ok (&$) {
	my ( $code, $desc ) = @_;
	local $Test::Builder::Level = $Test::Builder::Level + 1;

	my ( $ok, $error ) = _eval($code);

	ok($ok, $desc );

	diag "error: $@" unless $ok;
}

sub throws_ok (&$$) {
	my ( $code, $regex, $desc ) = @_;
	local $Test::Builder::Level = $Test::Builder::Level + 1;

	my ( $ok, $error ) = _eval($code);

	if ( $ok ) {
		fail($desc);
	} else {
		like($error || '', $regex, $desc );
	}
}


lives_ok {
	try {
		die "foo";
	};
} "basic try";

throws_ok {
	try {
		die "foo";
	} catch { die $_ };
} qr/foo/, "rethrow";


{
	local $@ = "magic";
	is( try { 42 }, 42, "try block evaluated" );
	is( $@, "magic", '$@ untouched' );
}

{
	local $@ = "magic";
	is( try { die "foo" }, undef, "try block died" );
	is( $@, "magic", '$@ untouched' );
}

{
	local $@ = "magic";
	like( (try { die "foo" } catch { $_ }), qr/foo/, "catch block evaluated" );
	is( $@, "magic", '$@ untouched' );
}

is( scalar(try { "foo", "bar", "gorch" }), "gorch", "scalar context" );
is_deeply( [ try {qw(foo bar gorch)} ], [qw(foo bar gorch)], "list context" );



sub Evil::DESTROY {
	eval { "oh noes" };
}

sub Evil::new { bless { }, $_[0] }

{
	local $@ = "magic";
	local $_ = "other magic";

	try {
		my $object = Evil->new;
		die "foo";
	} catch {
		pass("catch invoked");
		local $TODO = "i don't think we can ever make this work sanely, maybe with SIG{__DIE__}";
		like($_, qr/foo/);
	};

	is( $@, "magic", '$@ untouched' );
	is( $_, "other magic", '$_ untouched' );
}
