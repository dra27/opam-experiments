%{
(**************************************************************************)
(*                                                                        *)
(*    Copyright 2015      MetaStack Solutions Ltd.                        *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 3.0 with linking exception. *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

open CygRepository

let fold_package lines =
  let get state curr prev test =
    match state with
      `Curr ->
        Option.default {version = ""; requires = []; install = None; source = None; message = None} curr
    | `Prev ->
        Option.default {version = ""; requires = []; install = None; source = None; message = None} prev
    | `Test ->
        Option.default {version = ""; requires = []; install = None; source = None; message = None} test
  in
  let put state item (categories, ldesc, sdesc, curr, prev, test) =
    match state with
      `Curr ->
        ((categories, ldesc, sdesc, Some item, prev, test), state)
    | `Prev ->
        ((categories, ldesc, sdesc, curr, Some item, test), state)
    | `Test ->
        ((categories, ldesc, sdesc, curr, prev, Some item), state)
  in
  let f ((categories, ldesc, sdesc, curr, prev, test) as acc, state) = function
    `Category categories ->
      ((categories, ldesc, sdesc, curr, prev, test), state)
  | `LDesc ldesc ->
      ((categories, ldesc, sdesc, curr, prev, test), state)
  | `SDesc sdesc ->
      ((categories, ldesc, sdesc, curr, prev, test), state)
  | `Version version ->
      put state {(get state curr prev test) with version} acc
  | `Requires requires ->
      put state {(get state curr prev test) with requires} acc
  | `Install file ->
      put state {(get state curr prev test) with install = Some file} acc
  | `Source file ->
      put state {(get state curr prev test) with source = Some file} acc
  | `Message msg ->
      put state {(get state curr prev test) with message = Some msg} acc
  | `VersionSection state ->
      (acc, state)
  in
    fst (List.fold_left f (([], "", "", None, None, None), `Curr) lines)
%}

%token DEFINITION
%token EOF EOL
%token <string> String
%token <string> Section
%token <int64> Number
%token <string> MD5 SHA512 BASE64URL
%token ARCH CATEGORY INSTALL LDESC MESSAGE RELEASE REQUIRES SDESC TSTAMP SVERSION SOURCE VERSION
%token PREV CURR TEST
%token CYGWIN X86 X86_64

%type <CygRepository.t> parse
%start parse
%%

parse:
  header packages
   {let (a, b, c, d) =
      let f (a, b, c, d) = function
        `Release a ->
          (Some a, b, c, d)
      | `Arch b ->
          (a, Some b, c, d)
      | `SetupTimestamp c ->
          (a, b, Some c, d)
      | `SetupVersion d ->
          (a, b, c, Some d)
      in
        List.fold_left f (None, None, None, None) $1
    in
      (a, b, c, d, $2)}
;

packages:
  EOL packages
   {$2}
| DEFINITION String EOL packageDefinition packages
   {($2, fold_package $4)::$5}
| EOF
   {[]}
;

packageDefinition:
  packageDefinitionItem EOL packageDefinition
   {$1::$3}
| packageDefinitionItem EOL
   {[$1]}
;

packageDefinitionItem:
  CATEGORY categories
   {`Category $2}
| LDESC String
   {`LDesc $2}
| SDESC String
   {`SDesc $2}
| INSTALL String Number checksum
   {`Install ($2, $3, $4)}
| MESSAGE String String
   {`Message ($2, $3)}
| REQUIRES categories
   {`Requires $2}
| SOURCE String Number checksum
   {`Source ($2, $3, $4)}
| VERSION String
   {`Version $2}
| VERSION Number
   {`Version (Int64.to_string $2)}
| versionHeader
   {`VersionSection $1}
;

categories:
  String
   {[$1]}
| String categories
   {$1::$2}
;

versionHeader:
  CURR
   {`Curr}
| PREV
   {`Prev}
| TEST
   {`Test}
;

checksum:
  SHA512
   {SHA512Sum $1}
| MD5
   {MD5Sum $1}
| BASE64URL
   {Base64URL $1}
;

header:
  headerItem EOL
   {[$1]}
| headerItem EOL header
   {$1::$3}
;

headerItem:
  RELEASE String
   {if $2 = "cygwin"
    then `Release Cygwin
    else raise Parse_error}
| ARCH arch
   {`Arch $2}
| TSTAMP Number
   {`SetupTimestamp (Int64.to_float $2)}
| SVERSION String
   {`SetupVersion $2}
;

arch:
  X86
   {X86}
| X86_64
   {X86_64}
;
