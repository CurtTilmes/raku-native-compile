# Native::Compile - Native Compiling for Raku Modules

# SYNOPSIS

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
                        %( :os<darwin>,
                           :version(v10.14+),        # Version comparisons
                           :url<http://somewhere/mylib.dylib>,
                           :hash<abcd343534...> ) ]
      }
    }

# DESCRIPTION

Compile C and C++ sources, linking them into a shared library in the
module resources.  If a prebuilt library is available for Windows or
Mac OS/X, it can download it if a compiler is not available.

This module also exports a `MAIN` subroutine so you can make your
`Build.rakumod` executable and things will just work.  It takes the
*-v* / *--verbose* and *-n* / *--dryrun* flags and passes them on to
the `Build.build()`, which can be useful for debugging the build
process.

It exports a number of subroutines that capture what I've observed as
frequent boilerplate for doing this sort of thing throughout the
ecosystem.  Many examples seem to do it slightly differently, and I'm
not sure this is yet optimal.  This is still a work in progress, and
the interface may still change.  I'd like to support the most common
cases here, making easy things easy.  Hopefully the **build**
subroutine is all you really need, though the other functions are
exposed if they are useful.  You can manually perform the compile/link
steps in class `Build` if needed.

This module is modelled after, and draws from LibraryMake. It doesn't have
the full capabilities of LibraryMake, but for very simple and common cases,
it reduces the amount of required boilerplate. If you need more complex
capabilities, just write a full Makefile and use LibraryMake.

That said, if there is a capability you think would fit into this module,
please propose, either an idea, or even a patch.

# SUBROUTINES

### sub get-vars(*%args)

Get various compiling variables ala LibraryMake Many of the variables
are retrieved from the VM, based on the original system
compilation. Some are overridden by more appropriate choice. Each of
the variables can also be overridden by named parameters passed in to
this routine, and finally by Environment variables.

### sub win-hash($path, :$verbose, :$dryrun)

Use Windows powershell to compute a sha256 hash of a file

### sub win-fetch($url, $file, :$verbose, :$dryrun)

Use Windows powershell to download a file from a url

### sub openssl-hash($path, :$verbose, :$dryrun)

Use openssl to compute a sha256 hash

### sub curl-fetch($url, $file, :$verbose, :$dryrun)

Use curl to download a file from a url

### sub compile($src, :$obj, *%args)

Compile a single source file with the right compiler.  Can override
defaults with params :cc, :cxx, :cflags, :cxxflags, :extra-cxxflags,
:ccswitch, :ccout or the usual :verbose or :dryrun. Returns the path
to the compiled object.

### sub link($lib, @obj, :$dir = "resources/libraries", :$cpp, *%args)

Link objects into a shared library, defaulting to the
`resources/libraries` directory. The library name is mangled to match
the system (e.g. `.so`, `.dylib`, `.dll`). Set the :cpp flag to foce
use of the C++ to link so symbols will work right. Can override
defaults with params :cxxld, :ld, :ldflags, :extra-ldflags, :ldshared,
:ldout or the usual :verbose or :dryrun

### sub fetch( :$lib, :$url, :$hash, :$dir = "resources/libraries", *%args)

Fetch a library from a URL, name mangle the library and install into
resources/libraries by default, pass in :verbose or :dryrun as usual

### sub fallback($lib, @fallback, *%args)

Process a list of fallback library fetching alternatives, each with a
condition block, a url for the library, and a sha256 hash for the
library.

### sub build(:$lib, :@src, :@fallback, :$clean, :$dir, *%args)

Build a library from sources in directory :dir compile each source
file, then link. Pass in :clean to remove objects after linking. Other
named parameters passed in are forwarded to the
compiler/linker. Additionally a fallback list will be processed on any
error if present.

### sub MAIN(Str :$dir = ".", Bool :n(:$dryrun), Bool :v(:$verbose))

For command line building

# LICENSE

This work is subject to the Artistic License 2.0.
