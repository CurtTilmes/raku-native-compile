#!/usr/bin/env raku
use Test;
use Native::Compile;

class Build {
    method build($dir) {
        indir $*PROGRAM.parent,
        {
            plan 7;

            isa-ok my $vars = get-vars(:verbose, :dryrun), Hash, 'get-vars';

            ok $vars<VERBOSE>, 'verbose';
            ok $vars<DRYRUN>, 'dryrun';

            %*ENV<LDFLAGS> = '-fPIC';
            isa-ok $vars = get-vars, Hash, 'get-vars, ENV override';

            nok $vars<VERBOSE>, 'no verbose';
            nok $vars<DRYRUN>, 'no dry run';
            is $vars<LDFLAGS>, '-fPIC', 'ENV override';

            done-testing;
        }
    }
}
