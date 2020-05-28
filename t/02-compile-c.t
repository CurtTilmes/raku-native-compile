#!/usr/bin/env raku
use Test;
use Text:When <release>;
use Native::Compile;
use NativeCall;

sub hello(--> Str) is native('./resources/libraries/mylib') {}

class Build
{
    method build($dir)
    {
        indir $*PROGRAM.parent,
        {
            plan 6;

            ok my $obj = compile('myfile.c'), 'compile';

            ok $obj.e, 'object exists';

            ok my $lib = link('mylib', @$obj, :clean), 'link';

            nok $obj.e, 'object cleaned';

            ok $lib.e, 'library exists';

            is hello, "Hello, World!\n", 'called library ok';

            unlink $lib;

            rmdir $lib.parent, $lib.parent.parent;

            done-testing;
        }
    }
}
