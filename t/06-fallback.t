#!/usr/bin/env raku
use Test;
use Test::When <release online>;
use Native::Compile;

my $url = 'https://www.dropbox.com/s/dbi3607rbtqf140/testlib.dll?dl=1>';
my $hash = '916f58bd9f971116a4d7d49f1abea572fdb4313cb7ce203960f258c0f32f2555';

class Build
{
    method build($dir)
    {
        indir $*PROGRAM.parent,
        {
            plan 10;

            my $lib = fallback('mylib',
            [
                %( os => 'notmine', :$url, :$hash ),
            ]);

            nok $lib, "properly failed to fetch, os no match";

            $lib = fallback('mylib',
            [
                %( os => $*DISTRO.name, version => v0, :$url, :$hash ),
            ]);

            nok $lib, "properly failed to fetch, version no match";

            $lib = fallback('mylib',
            [
                %( os => $*DISTRO.name, version => v0+, :$url, :$hash ),
            ]);

            ok $lib, "Fetched library";

            ok $lib.e, 'library exists';

            unlink $lib;
            rmdir $lib.parent, $lib.parent.parent;

            ok $lib = build(dir => $*PROGRAM.parent,
                            :lib<mylib>,
                            :src<myfile.c>,
                            :cc<false>,      # This will foce the compile to fail
                            fallback => [ %( :$url, :$hash), ]
                ), 'build C library';

            ok $lib, "Fetched library, fallback from build";

            ok $lib.e, 'library exists';

            unlink $lib;
            rmdir $lib.parent, $lib.parent.parent;

            ok $lib = build(dir => $*PROGRAM.parent,
                            :lib<mylib>,
                            :src<myfile.c>,
                            :cc<false>,      # This will foce the compile to fail
                            fallback => [
                                %( os => 'notmine', :$url, :$hash ),
                                %( os => $*DISTRO.name, version => v0,
                                   :$url, :$hash ),
                                %( :$url, :$hash) ]
                ), 'build C library, several fallbacks';

            ok $lib, "Fetched library, fallback from build";

            ok $lib.e, 'library exists';

            unlink $lib;
            rmdir $lib.parent, $lib.parent.parent;

            done-testing;
        }
    }
}
