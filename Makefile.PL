#!/usr/bin/perl -w

use strict;

use ExtUtils::MakeMaker;

WriteMakefile(
	NAME         => 'Try::Tiny',
	VERSION_FROM => 'lib/Try/Tiny.pm',
	INSTALLDIRS  => 'site',
	SIGN         => 1,
	PL_FILES     => { },
	PREREQ_PM    => { },
);
