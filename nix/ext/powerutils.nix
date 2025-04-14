{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "powerutils";
  version = "2.6.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "powerbase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-QNfUpQjqHNzbNqBvjb5a3GtNH9hjbBMDUK19xUU3LpI=";
  };

  installPhase = ''
    mkdir -p $out/lib

    install -D *${postgresql.dlSuffix} -t $out/lib
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/skorpland/${pname}";
    maintainers = with maintainers; [ steve-chavez ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
