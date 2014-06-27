#!/usr/bin/perl

@assets = `ls ../assets/evernote`;
chomp @assets;
@posts = `ls ../_posts/evernote`;

foreach $post (@posts) {
  open INPUT, "<../_posts/evernote/$post";
  $content = join('', <INPUT>);
  close INPUT;
  @matches = $content =~ /{{ ASSET_PATH }}\/evernote\/([a-z0-9-.@]*)/g;
  foreach $match (@matches) {
    @assets = grep { $_ ne $match } @assets;
  }
}

foreach $asset (@assets) {
  `git rm -f ../assets/evernote/$asset`;
}
