{
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

(**
 * Cygwin setup.ini Lexer.
 *)

(*
 * See https://sourceware.org/cygwin-apps/setup-head.ini.html (though as at 16-Jun-2015 many details
 * are missing). See also inilex.ll and iniparse.yy in git://cygwin.com/git/cygwin-setup.git
 *
 * Many of the more advanced features in the parser code were added in 2002, but have clearly never
 * been brought into action, so the handling of them in this parser is scant.
 *)

open CygParser

module StringMap = Map.Make(String)

let keywords =
  let keys =
    [("x86", X86); ("x86_64", X86_64)]
  in
    List.fold_left (fun acc (key, value) -> StringMap.add key value acc) StringMap.empty keys

let key_of_string =
  let keys =
    let keys =
      [("arch", ARCH); ("category", CATEGORY); ("Filename", INSTALL); ("install", INSTALL);
       ("ldesc", LDESC); ("message", MESSAGE); ("release", RELEASE); ("requires", REQUIRES);
       ("sdesc", SDESC); ("setup-timestamp", TSTAMP); ("setup-version", SVERSION);
       ("source", SOURCE); ("Version", VERSION); ("version", VERSION)]
    in
      List.fold_left (fun acc (key, value) -> StringMap.add key value acc) StringMap.empty keys
  in
    fun key f lexbuf ->
      try
        StringMap.find key keys
      with Not_found ->
        Printf.eprintf "Warning: skipping %s on line %d\n%!" key lexbuf.Lexing.lex_start_p.Lexing.pos_lnum;
        f lexbuf

let section_of_string = function
  "prev" -> PREV
| "curr" -> CURR
| "test" -> TEST
| "exp" -> TEST
| section -> Section section
}

let eol = [ ' ' '\t' ]* ('#' [^ '\r' '\n' ]*)? '\r'? '\n'
let toEOL = [^ '#' '\r' '\n' ]+
let str = [ '!' 'a'-'z' 'A'-'Z' '0'-'9' '_' '.' '/' ':' '\\' '+' '~' '-' ]+
let space = [ ' ' '\t' ]

(*
 * These are keys which support the multi-line versioned constraints (versionedpackagelist in
 * iniparse.yy). The grammar only permits the newline to appear after a comma, which is used to
 * provide an easy way to skip over these items.
 *)
let versionedPackageKeys =
  ("Conflicts" | "Depends" | "Pre-Depends" | "Recommends" | "Suggests" | "Replaces" |
   "Build-Depends" | "Build-Depends-Indep")

rule token = parse
  '#' [^ '\r' '\n' ]* '\r'? '\n'
   {token lexbuf}

| space+
   {token lexbuf}

| eol
   {EOL}

| eof
   {EOF}

| ('@' | "Package:")
   {DEFINITION}

| '[' ([^ ']' ]+ as section) ']'
   {section_of_string section}

| versionedPackageKeys as key ':'
   {Printf.eprintf "Warning: skipping %s on line %d\n%!" key lexbuf.Lexing.lex_start_p.Lexing.pos_lnum;
    skipVersionedPackageList lexbuf}

| ([ 'a'-'z' 'A'-'Z' '-' ]+ as key) ":"
   {key_of_string key skipToEOL lexbuf}

| '"' ([^ '"' ]* as value) '"'
   {String value}

| ([ '0'-'9' ]+ as number)
   {Number (Int64.of_string number)}

| ([ '0'-'9' 'a'-'f' ]+ as checksum)
   {match String.length checksum with
     32 ->
       MD5 checksum
    | 128 ->
       SHA512 checksum
    | 86 ->
       BASE64URL checksum
    | _ ->
       String checksum}

| [ 'a'-'z' '_' '0'-'9' ]+ as keyword
   {try
      StringMap.find keyword keywords
    with Not_found ->
      String keyword}

| str as str
   {String str}

and skipToEOL = parse
  toEOL eol
   {token lexbuf}

| toEOL eof
   {EOF}

and skipVersionedPackageList = parse
  toEOL ',' eol
   {Lexing.new_line lexbuf;
    skipVersionedPackageList lexbuf}

| toEOL eof
   {EOF}

| toEOL eol
   {Lexing.new_line lexbuf;
    token lexbuf}
