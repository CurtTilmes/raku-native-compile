#!/usr/bin/env raku
use Test;
use Test::When <release>;
use Native::Compile;
use NativeCall;

sub hello(--> Str) is native('./resources/libraries/mylib') {}

class Build
{
    method build($dir)
    {
        indir $*PROGRAM.parent,
        {
            plan 3;

            ok my $lib = build(dir => $*PROGRAM.parent,
                               :lib<mylib>,
                               :src<myfile.cpp>,
                               :clean), 'build C++ library';

            ok $lib.e, 'library exists';

            is hello, "Hello, World!\n", 'called library ok';

            unlink $lib;

            rmdir $lib.parent, $lib.parent.parent;

            done-testing;
        }
    }
}
