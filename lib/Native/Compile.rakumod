unit module Native::Compile;

=begin pod

=head1 NAME

Native::Compile - Native Compiling for Raku Modules

=head1 SYNOPSIS

  # META6.json
  "resources" : [ "libraries/mylib" ]

  # MyModule.rakumod
  my constant LIB = %?RESOURCES<libraries/mylib>;
  sub myfunc() is native(LIB) {}

  # A Simple Build.rakumod example:
  use Native::Compile;
  class Build {
    method build($dir) {
        build :$dir, :lib<mylib>, :src<src/myfile.c>
    }
  }

  # More explicit separate steps Build.rakumod:
  use Native::Compile;
  class Build {
      method build($dir) {
          indir $dir, {
              my $obj = compile('src/myfile.c');
              link('mylib', @$obj);
          }
      }
  }

  # A more complicated Build.rakumod:
  use Native::Compile;
  class Build {
    method build($dir, :$verbose, :$dryrun) {
        build :$dir, :lib<mylib>, :src<src/myfile.c>, :cc<clang>,
        :extra-cflags<-O>, :$verbose, :$dryrun, :clean,
        fallback => [ %( :os<windows>              # special name for windows
                         :url<http://somewhere/mylib.dll>,
                         :hash<abcd343534...> ),   # SHA256
                      %( :os<darwin>
                         :version(v10.14+),        # Version comparisons
                         :url<http://somewhere/mylib.dylib>,
                         :hash<abcd343534...> ) ]
    }
  }

=head1 DESCRIPTION

Compile C and C++ sources, linking them into a shared library in the
module resources.  If a prebuilt library is available for Windows or
Mac OS/X, it can download it if a compiler is not available.

This module also exports a B<MAIN> subroutine so you can make your
C<Build.rakumod> executable and things will just work.  It takes the
'-v/--verbose' and '-n/--dryrun' flags and passes them on to the
C<Build.build()>, which can be useful for debugging the build process.

It exports a number of subroutines that capture what I've observed as
frequent boilerplate for doing this sort of thing throughout the
ecosystem.  Many examples seem to do it slightly differently, and I'm
not sure this is yet optimal.  This is still a work in progress, and
the interface may still change.  I'd like to support the most common
cases here, making easy things easy.  Hopefully the B<build>
subroutine is all you really need, though the other functions are
exposed if they are useful.  You can manually perform the compile/link
steps in class C<Build> if needed.


=head1 SUBROUTINES

=end pod

use HTTP::UserAgent;
use JSON::Fast;

subset CPPSRC of Str where *.IO.extension eq 'cpp';
subset CSRC   of Str where *.IO.extension eq 'c';

my %defaults;

INIT
{
    given $*VM
    {
        when .name ~~ 'moar'
        {
            %defaults<O>        = .config<obj>;
            %defaults<SO>       = .config<dll>;
            %defaults<SO>          ~~ s/^.*\%s//;
            %defaults<CC>       = .config<cc>;
            %defaults<CCSHARED> = .config<ccshared>;
            %defaults<CCOUT>    = .config<ccout>;
	    %defaults<CCSWITCH> = .config<ccswitch>;
            %defaults<CFLAGS>   = .config<cflags>;
            %defaults<LD>       = .config<ld>;
            %defaults<LDSHARED> = .config<ldshared>;
            %defaults<LDFLAGS>  = .config<ldflags>;
            %defaults<LIBS>     = .config<ldlibs>;
            %defaults<LDOUT>    = .config<ldout>;
        }
        when .name ~~ 'jvm'
        {
            %defaults<O>        = .config<nativecall.o>;
            %defaults<SO>       = '.' ~ .config<nativecall.so>;
            %defaults<CC>       = .config<nativecall.cc>;
            %defaults<CCSHARED> = .config<nativecall.ccdlflags>;
            %defaults<CCOUT>    = '-o';
	    %defaults<CCSWITCH> = .config<nativecall.ccswitch>;
            %defaults<CFLAGS>   = .config<nativecall.ccflags>;

            %defaults<LD>       = .config<nativecall.ld>;
            %defaults<LDSHARED> = .config<nativecall.lddlflags>;
            %defaults<LDFLAGS>  = .config<nativecall.ldflags>;
            %defaults<LIBS>     = .config<nativecall.perllibs>;
            %defaults<LDOUT>    = .config<nativecall.ldout>;
        }
        default
        {
            die "Unknown VM; don't know how to build";
        }
    }

    if $*DISTRO.is-win
    {
        if run 'cl', :out
        {
            %defaults<CXX> = 'cl';
	    %defaults<CXXFLAGS> = '/nologo /EHsc /std:c++latest';
        }
        elsif run 'g++', '--version', :out
        {
            %defaults<CXX> = 'g++';
        }
        %defaults<CXXLD> = %defaults<LD>;
	%defaults<LDFLAGS> = '/nologo';
    }
    else
    {
        for <c++ g++ clang++> -> $compiler
        {
            if run $compiler, '--version', :out
            {
                %defaults<CXX> = $compiler;
                last
            }
        }
        %defaults<CXXLD> = %defaults<CXX>;
    }

    %defaults<CXXFLAGS> //= %defaults<CFLAGS>;

    %defaults{$_} = '' for <EXTRA-CFLAGS EXTRA-CXXFLAGS EXTRA-LDFLAGS EXTRA-LIBS
                            DRYRUN VERBOSE>;
}

#|( Get various compiling variables ala LibraryMake
Many of the variables are retrieved from the VM, based on the original
system compilation.  Some are overridden by more appropriate choice.

Each of the variables can also be overridden by named parameters
passed in to this routine, and finally by Environment variables.
)
sub get-vars(*%args --> Hash:D) is export  # Adapted from LibraryMake
{
    my %vars = %defaults;

    for %args.kv -> $k, $v
    {
        %vars{$k.uc} = $v;
    }

    for %vars.kv -> $k, $v
    {
        %vars{$k} [R//]= %*ENV{$k};
    }

    return %vars
}


#| Use Windows powershell to compute a sha256 hash of a file
sub win-hash($path, :$verbose, :$dryrun --> Str:D) is export
{
    my @cmd = 'powershell', '-noprofile', '-Command',
              "(Get-FileHash -Path $path).Hash";
    put @cmd if $verbose;
    return 'nohash' if $dryrun;
    my $proc = run |@cmd, :out;
    chomp $proc.out.slurp(:close);
}

#| Use Windows powershell to download a file from a url
sub win-fetch($url, $file, :$verbose, :$dryrun) is export
{
    my @cmd = 'powershell', '-noprofile', '-Command',
              "Invoke-WebRequest -OutFile $file $url";
    put @cmd if $verbose;
    run @cmd unless $dryrun;
}

#| Use openssl to compute a sha256 hash
sub openssl-hash($path, :$verbose, :$dryrun) is export
{
    my @cmd = 'openssl', 'dgst', '-sha256', '-hex', ~$path;
    put @cmd if $verbose;
    return 'nohash' if $dryrun;
    my $proc = run |@cmd, :out;
    $proc.out.slurp(:close) ~~ /' ' (<xdigit> ** 64)/;
    return ~$0
}

#| Use curl to download a file from a url
sub curl-fetch($url, $file, :$verbose, :$dryrun) is export
{
    my @cmd = 'curl', '-L', '-s', '-o', $file, $url;
    put @cmd if $verbose;
    run @cmd unless $dryrun;
}

#| Use sha256sum to compute a sha256 hash
sub sha256sum($path, :$verbose, :$dryrun) is export
{
    my @cmd = 'sha256sum', $path;
    put @cmd if $verbose;
    return 'nohash' if $dryrun;
    my $proc = run |@cmd, :out;
    $proc.out.slurp(:close) ~~ /^(<xdigit> ** 64)/;
    return ~$0;
}

#| Use HTTP::Agent to download a file from a url
sub http-fetch($url, $file, :$verbose, :$dryrun) is export
{
    put 'Getting $url' if $verbose;
    my $ua = HTTP::UserAgent.new;
    my $response = $ua.get($url);
    die $response.status-line unless $response.is-success;
    spurt $file, $response.content;
}

#|( Compile a single .cpp source file with a C++ compiler
Can override defaults with params :cxx, :cxxflags, :extra-cxxflags,
:ccswitch, :ccout or the usual :verbose or :dryrun.  Returns the
path to the compiled object.)
multi compile(CPPSRC $src, :$obj is copy, *%args --> IO::Path:D) is export
{
    my %vars = get-vars(|%args);
    die "C++ Compiler not found" unless %vars<CXX>;
    $obj //= $src.IO.extension(%vars<O>, :joiner('')),
    my @cmd = %vars<CXX>, %vars<CXXFLAGS>, %vars<EXTRA-CXXFLAGS>,
              %vars<CCSWITCH>, $src, %vars<CCOUT> ~ $obj.absolute;
    put @cmd if %vars<VERBOSE>;
    shell(@cmd) unless %vars<DRYRUN>;
    return $obj;
}

#|( Compile a single .c source file with a C compiler Can override
defaults with params :cc, :cflags, :extra-cflags, :ccswitch,
:ccout or the usual :verbose or :dryrun.  Returns the path to the
compiled object.)
multi compile(CSRC $src, :$obj is copy, *%args) is export
{
    my %vars = get-vars(|%args);
    $obj //= $src.IO.extension(%vars<O>, :joiner('')),
    my @cmd = %vars<CC>, %vars<CFLAGS>, %vars<EXTRA-CFLAGS>,
              %vars<CCSWITCH>, $src, %vars<CCOUT> ~ $obj.absolute;
    put @cmd if %vars<VERBOSE>;
    shell(@cmd) unless %vars<DRYRUN>;
    return $obj;
}

#|( Link objects into a shared library, defaulting to the
resources/libraries directory.  The library name is mangled to matc
the system (e.g. .so, .dylib, .dll).  Set the :cpp flag to foce use of
the C++ to link so symbols will work right.  Can override defaults
with params :cxxld, :ld, :ldflags, :extra-ldflags, :ldshared, :ldout
or the usual :verbose or :dryrun)
sub link($lib, @obj, :$dir = 'resources/libraries', :$cpp, :$clean, *%args)
    is export
{
    my %vars = get-vars(|%args);
    my $destdir = $dir.IO;
    $destdir.mkdir unless %vars<DRYRUN>;
    my $lib-name = $*VM.platform-library-name($lib.IO);
    my $libpath = $destdir.add($lib-name);
    my @cmd = ($cpp ?? %vars<CXXLD> !! %vars<LD>),
              %vars<LDFLAGS>, %vars<EXTRA-LDFLAGS>, %vars<LDSHARED>,
              %vars<LDOUT> ~ $libpath.absolute, @obj;
    put @cmd if %vars<VERBOSE>;
    return $libpath if %vars<DRYRUN>;
    shell(@cmd);
    unlink $libpath.extension('exp'), $libpath.extension('lib');
    unlink @obj if $clean;
    return $libpath;
}

#|( Fetch a library from a URL, name mangle the library and install
into resources/libraries by default, pass in :verbose or :dryrun as
usual)
multi fetch(:$lib, :$url, :$hash, :$dir = 'resources/libraries', *%args)
     is export
{
    my %vars = get-vars(|%args);
    my $destdir = $dir.IO;
    $destdir.mkdir unless %vars<DRYRUN>;
    my $lib-name = $*VM.platform-library-name($lib.IO);
    my $path = $destdir.add($lib-name);

    put "Fetching $url for $path" if %vars<VERBOSE>;

    my $got-hash;
    if $*DISTRO.is-win                 # Use powershell
    {
        win-fetch($url, $path, :verbose(%vars<VERBOSE>),
                  :dryrun(%vars<DRYRUN>));

        $got-hash = win-hash($path, :verbose(%vars<VERBOSE>),
                             :dryrun(%vars<DRYRUN>));
    }
    elsif $*DISTRO.name eq 'darwin'  # curl and openssl come with darwin
    {
	curl-fetch($url, $path, :verbose(%vars<VERBOSE>),
		   :dryrun(%vars<DRYRUN>));

	$got-hash = openssl-hash($path, :verbose(%vars<VERBOSE>),
				 :dryrun(%vars<DRYRUN>));
    }
    else # Linux usually has sha256sum... we can hope...
    {
        http-fetch($url, $path, :verbose(%vars<VERBOSE>),
		   :dryrun(%vars<DRYRUN>));

        $got-hash = sha256sum($path, :verbose(%vars<VERBOSE>),
			      :dryrun(%vars<DRYRUN>));
    }

    return $path if %vars<DRYRUN>;

    die "Bad download, Got: $got-hash instead of $hash"
        unless $hash.lc eq $got-hash.lc;

    return $path
}

#|( Process a list of fallback library fetching alternatives, each
possibly with an os/version, a url for the library, and a sha256 hash for
the library.)
sub fallback($lib, @fallback, *%args) is export
{
    for @fallback -> % (:$os, :$version, :$url, :$hash)
    {
        next if $os && (($os eq 'windows' and !$*DISTRO.is-win)
                        || ($os ne $*DISTRO.name));
        next if $version && $*DISTRO.version !~~ $version;
        return $_ with fetch(:$lib, :$url, :$hash, |%args);
    }
    False
}

#|( Build a library from sources in directory :dir compile each source
file, then link. Pass in :clean to remove objects after linking. Other
named parameters passed in are forwarded to the compiler/linker.
Additionally a fallback list will be processed on any error if
present.)
multi build(:$lib, :$src, :@fallback, :$clean, :$dir, *%args) is export
{
    indir $dir,
    {
        my $cpp;
        my @obj = do for @$src -> $file
        {
            $cpp = True if $file.IO.extension eq 'cpp';

            compile($file.IO.absolute, |%args)
        }

        return link($lib, @obj, :$clean, :$cpp, |%args);

        CATCH
        {
            default
            {
                return @fallback ?? fallback($lib, @fallback, |%args)
                                 !! False
            }
        }
    }
}

#|(For commandline building)
multi MAIN(Bool :n(:$dryrun), Bool :v(:$verbose)) is export
{
    return if $*PROGRAM eq '-e';  # Run only if command line
    ::('Build').new.build('.', :$verbose, :$dryrun)
}

=begin pod

=head1 LICENSE

This work is subject to the Artistic License 2.0.

=end pod
