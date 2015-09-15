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
 * Cygwin repository.
 *)

type release = Cygwin

type arch = X86
          | X86_64

type checksum = SHA512Sum of string
              | MD5Sum of string
              | Base64URL of string

type version = {version: string;
                requires: string list;
                install: (string * int64 * checksum) option;
                source: (string * int64 * checksum) option;
                message: (string * string) option}

(**
 * Cygwin Repository Information.
 *)
type t = release option * arch option * float option * string option * (string * (string list * string * string * version option * version option * version option)) list

exception CorruptRepository
exception CategoriesNotKnown of string list
exception PackagesNotKnown of string list

val is_valid : t -> string list
(**
 * [is_valid repository] returns a list of warnings about the consistency of the given repository. A
 * completely valid repository will return [[]].
 *)

val select : t -> ?inverse:bool -> ?strip:bool -> string list -> string list -> t
(**
 * [select repository categories packages] returns a repository containing [packages], any other
 * packages in [categories] along with their dependencies. If [~strip] is [true] (default: [false])
 * then [prev] and [test] details are removed from the repository along with source files for
 * [curr].
 *
 * @raise CorruptRepository if any selected package doesn't have an installation definition
 * @raise CategoriesNotKnown if a category resulted in no packages being selected
 * @raise PackagesNotKnown if any packages specified weren't in the repository
 *)

val parse_mirrors : string -> (string * string) list Map.Make(String).t
(**
 * [parse_mirrors data] converts a Cygwin mirrors.lst file to map from locations to repository URLs.
 * Each line of [data] (which can use either CRLF or LF line-endings) consists of four
 * semicolon-separated fields: URL, description (which is the host name), region and country/state.
 *
 * The data in the map are lists of [(url, description)] pairs. The key [""] contains all the
 * mirrors. Each entry is added to the key for region and region/country. The URLs are guaranteed to
 * end in a forward slash.
 *
 * @raise CorruptRepository if [data] cannot be interpreted.
 *)

val string_of_repo : t -> string
(**
 * Converts a repository to its string representation (for serialising)
 *)

val mirrors_url : string
(**
 * Location of Cygwin's mirrors.lst
 *)

val setup_url : arch -> string
(**
 * [setup_url arch] returns the URL to the Cygwin setup program for the given architecture.
 *)

val ini_path : arch -> string
(**
 * [ini_path arch] returns the path to setup.ini for the given architecture within a mirror.
 *)

val download_repository : string list -> t -> string -> unit

(* @@DRA Temporary *)
val download : ?ch:out_channel -> ?show_msg:bool -> string -> string * int
val do_mkdir : string -> unit
