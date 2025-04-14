{ lib, stdenv, fetchFromGitHub, curl, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_net";
  version = "0.14.0";

  buildInputs = [ curl postgresql ];

  src = fetchFromGitHub {
    owner = "powerbase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-c1pxhTyrE5j6dY+M5eKAboQNofIORS+Dccz+7HKEKQI=";
  };

  env.NIX_CFLAGS_COMPILE = "-Wno-error";

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp sql/*.sql $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Async networking for Postgres";
    homepage = "https://github.com/skorpland/pg_net";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
