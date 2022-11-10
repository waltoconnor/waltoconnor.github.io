with import <nixpkgs> { };


  stdenv.mkDerivation rec {
    name = "waltoconnor.dev";
    buildInputs = [ 
      jekyll 
      ruby 
      rubyPackages.jekyll-feed
      rubyPackages.jekyll-paginate
      rubyPackages.jekyll-redirect-from
      rubyPackages.jekyll-commonmark
      rubyPackages.jekyll-include-cache
      rubyPackages.jekyll-remote-theme
      ];

  }
