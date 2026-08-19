#!/usr/bin/perl
# Injects inline `style` margins onto block tags in a pandoc HTML fragment.
# Reads from stdin, writes to stdout.
#
# Why: pandoc's fragment output emits bare <p>/<ul>/<ol>/<li> with no
# attributes, relying on the browser's default user-agent stylesheet for
# paragraph/list spacing. Paste targets with their own editor CSS (Microsoft
# Teams' rich-text editor resets <p>/<ul> margins to 0) collapse all
# vertical spacing between blocks as a result — measured: pasting multiple
# paragraphs and a list into Teams produced zero gap between them, even
# though the same HTML renders with normal spacing in a plain browser tab.
# Inline `style` attributes survive most paste sanitizers (unlike <style>
# blocks or CSS classes, which have nothing to resolve against in the
# target's own stylesheet), so spacing is set explicitly here instead of
# left to the target's UA stylesheet.
use strict;
use warnings;

my %style = (
  p  => 'margin:0 0 12px 0',
  ul => 'margin:0 0 12px 0;padding-left:20px',
  ol => 'margin:0 0 12px 0;padding-left:20px',
  li => 'margin:0 0 4px 0',
);

while (<STDIN>) {
  s{<(p|ul|ol|li)((?:\s[^>]*)?)>}{'<' . $1 . $2 . ' style="' . $style{$1} . '">'}ge;
  print;
}
