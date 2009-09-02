package Try::Tiny;

use strict;
#use warnings;

use vars qw(@EXPORT @EXPORT_OK $VERSION @ISA);

BEGIN {
	require Exporter;
	@ISA = qw(Exporter);
}

$VERSION = "0.02";

$VERSION = eval $VERSION;

@EXPORT = @EXPORT_OK = qw(try catch);

sub try (&;$) {
	my ( $try, $catch ) = @_;

	# we need to save this here, the eval block will be in scalar context due
	# to $failed
	my $wantarray = wantarray;

	my ( @ret, $error, $failed );

	# FIXME consider using local $SIG{__DIE__} to accumilate all errors. It's
	# not perfect, but we could provide a list of additional errors for
	# $catch->();

	{
		# localize $@ to prevent clobbering of previous value by a successful
		# eval.
		local $@;

		# failed will be true if the eval dies, because 1 will not be returned
		# from the eval body
		$failed = not eval {

			# evaluate the try block in the correct context
			if ( $wantarray ) {
				@ret = $try->();
			} elsif ( defined $wantarray ) {
				$ret[0] = $try->();
			} else {
				$try->();
			};

			return 1; # properly set $fail to false
		};

		# copy $@ to $error, when we leave this scope local $@ will revert $@
		# back to its previous value
		$error = $@;
	}

	# at this point $failed contains a true value if the eval died even if some
	# destructor overwrite $@ as the eval was unwinding.
	if ( $failed ) {
		# if we got an error, invoke the catch block.
		if ( $catch ) {
			# This works like given($error), but is backwards compatible and
			# sets $_ in the dynamic scope for the body of C<$catch>
			for ($error) {
				return $catch->($error);
			}

			# in case when() was used without an explicit return, the C<for>
			# loop will be aborted and there's no useful return value
		}

		return;
	} else {
		# no failure, $@ is back to what it was, everything is fine
		return $wantarray ? @ret : $ret[0];
	}
}

sub catch (&) {
	return $_[0];
}


__PACKAGE__

__END__

=pod

=head1 NAME

Try::Tiny - minimal try/catch with proper localization of $@

=head1 SYNOPSIS

	# handle errors with a catch handler
	try {
		die "foo";
	} catch {
		warn "caught error: $_";
	};

	# just silence errors
	try {
		die "foo";
	};

=head1 DESCRIPTION

This module provides bare bones C<try>/C<catch> statements that are designed to
minimize common mistakes with eval blocks, and NOTHING else.

This is unlike L<TryCatch> which provides a nice syntax and avoids adding
another call stack layer, and supports calling C<return> from the try block to
return from the parent subroutine. These extra features come at a cost of a few
dependencies, namely L<Devel::Declare> and L<Scope::Upper> which are
occasionally problematic, and the additional catch filtering uses L<Moose>
type constraints which may not be desirable either.

The main focus of this module is to provide simple and reliable error handling
for those having a hard time installing L<TryCatch>, but who still want to
write correct C<eval> blocks without 5 lines of boilerplate each time.

It's designed to work as correctly as possible in light of the various
pathological edge cases (see L<BACKGROUND>) and to be compatible with any style
of error values (simple strings, references, objects, overloaded objects, etc).

=head1 EXPORTS

All functions are exported by default using L<Exporter>.

In the future L<Sub::Exporter> may be used to allow the keywords to be renamed,
but this technically does not satisfy Adam Kennedy's definition of "Tiny".

=over 4

=item try (&;$)

Takes one mandatory try subroutine and one optional catch subroutine.

The mandatory subroutine is evaluated in the context of an C<eval> block.

If no error occurred the value from the first block is returned, preserving
list/scalar context.

If there was an error and the second subroutine was given it will be invoked
with the error in C<$_> (localized) and as that block's first and only
argument.

Note that the error may be false, but if that happens the C<catch> block will
still be invoked..

=item catch (&)

Intended to be used in the second argument position of C<try>.

Just returns the subroutine it was given.

	catch { ... }

is the same as

	sub { ... }

=back

=head1 BACKGROUND

There are a number of issues with C<eval>.

=head2 Clobbering $@

When you run an eval block and it succeeds, C<$@> will be cleared, potentially
clobbering an error that is currently being caught.

This causes action at a distance, clearing previous errors your caller may have
not yet handled.

C<$@> must be properly localized before invoking C<eval> in order to avoid this
issue.

=head2 Localizing $@ silently masks errors

Inside an eval block C<die> behaves sort of like:

	sub die {
		$@_ = $_[0];
		return_undef_from_eval();
	}

This means that if you were polite and localized C<$@> you can't die in that
scope, or your error will be discarded (printing "Something's wrong" instead).

The workaround is very ugly:

	my $error = do {
		local $@;
		eval { ... };
		$@;
	};

	...
	die $error;

=head2 $@ might not be a true value

This code is wrong:

	if ( $@ ) {
		...
	}

because due to the previous caveats it may have been unset.

C<$@> could also an overloaded error object that evaluates to false, but that's
asking for trouble anyway.

The classic failure mode is:

	sub Object::DESTROY {
		eval { ... }
	}

	eval {
		my $obj = Object->new;

		die "foo";
	};

	if ( $@ ) {

	}

In this case since C<Object::DESTROY> is not localizing C<$@> but still uses
C<eval> it will set C<$@> to C<"">.

The destructor is called when the stack is unwound, after C<die> sets C<$@> to
C<"foo at Foo.pm line 42\n">, so by the time C<if ( $@ )> is evaluated it has
been cleared by C<eval> in the destructor.

The workaround for this is even uglier than the previous ones. Even though we
can't save the value of C<$@> from code that doesn't localize, we can at least
be sure the eval was aborted due to an error:

	my $failed = not eval {
		...

		return 1;
	};

This is because an C<eval> that caught a C<die> will always return a false
value.

=head1 SHINY SYNTAX

Using Perl 5.10 you can use L<perlsyn/"Switch statements">.

The C<catch> block is invoked in a topicalizer context (like a C<given> block),
but note that you can't return a useful value from C<catch> using the C<when>
blocks without an explicit C<return>.

This is somewhat similar to Perl 6's C<CATCH> blocks. You can use it to
concisely match errors:

	try {
		require Foo;
	} catch {
		when (/^Can't locate .*?\.pm in \@INC/) { } # ignore
		default { die $_ }
	};

=head1 CAVEATS

=over 4

=item *

C<try> introduces another caller stack frame. L<Sub::Uplevel> is not used. L<Carp>
will report this when using full stack traces. This lack of magic is considered
a feature.

=item *

The value of C<$_> in the C<catch> block is not guaranteed to be preserved,
there is no safe way to ensure this if C<eval> is used unhygenically in
destructors. It's only guaranteeed that the C<catch> will be called.

=back

=head1 SEE ALSO

=over 4

=item L<TryCatch>

Much more feature complete, more convenient semantics, but at the cost of
implementation complexity.

=item L<autodie>

Automatic error throwing for builtin functions and more. Also designed to
work well with C<given>/C<when>.

=item L<Throwable>

A lightweight role for rolling your own exception classes.

=item L<Error>

Exception object implementation with a C<try> statement. Does not localize
C<$@>.

=item L<Exception::Class::TryCatch>

Provides a C<catch> statement, but properly calling C<eval> is your
responsibility.

The C<try> keyword pushes C<$@> onto an error stack, avoiding some of the
issues with C<$@> but you still need to localize to prevent clobbering.

=back

=head1 VERSION CONTROL

L<http://github.com/nothingmuch/try-tiny/>

=head1 AUTHOR

Yuval Kogman E<lt>nothingmuch@woobling.orgE<gt>

=head1 COPYRIGHT

	Copyright (c) 2009 Yuval Kogman. All rights reserved.
	This program is free software; you can redistribute
	it and/or modify it under the terms of the MIT license.

=cut

