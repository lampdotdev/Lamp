#!/bin/zsh
# Copies the look of the light on an app being changed (Sources/Lamp/TransitionLook.swift, between its
# markers) into the support code every app gets (Template.swift), where the app draws it. TransitionLookTests
# fails while the two differ.
set -euo pipefail
cd "${0:A:h}/.."
/usr/bin/perl -0777 -e '
    open my $f, "<", "Sources/Lamp/TransitionLook.swift" or die;
    local $/; my $look = <$f>;
    $look =~ /^(    \/\/ TransitionLook\n.*?^    \/\/ end TransitionLook\n)/ms or die "no markers in TransitionLook.swift\n";
    my $block = $1;
    $block =~ s/^(?=.)/    /mg;   # the template holds it one level deeper, inside LampTransition
    my $template = <STDIN>;
    $template =~ s/^        \/\/ TransitionLook\n.*?^        \/\/ end TransitionLook\n/$block/ms or die "no markers in Template.swift\n";
    print $template;
' < Sources/Lamp/Template.swift > Sources/Lamp/Template.swift.new
mv Sources/Lamp/Template.swift.new Sources/Lamp/Template.swift
echo "Copied the transition's look into Template.swift."
