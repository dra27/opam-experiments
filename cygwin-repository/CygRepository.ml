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

module StringSet = Set.Make(String)
module StringMap = Map.Make(String)

let is_valid (release, arch, timestamp, version, packages) =
  let warnings =
    if release = None
    then ["release header missing"]
    else [] in
  let warnings =
    if arch = None
    then "arch header missing"::warnings
    else warnings in
  let warnings =
    if timestamp = None
    then "setup-timestamp header missing"::warnings
    else warnings in
  let warnings =
    if version = None
    then "setup-version header missing"::warnings
    else warnings in
  let (warnings, all_packages) =
    let f (warnings, acc) (name, _) =
      if StringSet.mem name acc
      then ((Printf.sprintf "Package %s defined twice" name)::warnings, acc)
      else (warnings, StringSet.add name acc) in
    List.fold_left f (warnings, StringSet.empty) packages in
  let f warnings (name, (_, _, _, curr, prev, test)) =
    let validate_file section warnings = function
      None ->
        warnings
    | Some {version; requires; install; _} ->
      let warnings =
        if version = ""
        then (Printf.sprintf "Package %s %s definition missing version" name section)::warnings
        else warnings in
      let warnings =
        let f warnings package =
          if StringSet.mem package all_packages
          then warnings
          else (Printf.sprintf "Package %s %s definition refers to non-existent package %s" name section package)::warnings in
        List.fold_left f warnings requires in
      let warnings =
        if List.mem name requires
        then (Printf.sprintf "Package %s %s definition depends on itself!" name section)::warnings
        else warnings
      in
        if install = None
        then (Printf.sprintf "Package %s %s definition doesn't have an installation binary" name section)::warnings
        else warnings
    in
      let warnings =
        if curr = None
        then (Printf.sprintf "Package %s missing an installation definition" name)::warnings
        else validate_file "installation" warnings curr in
      let warnings =
        validate_file "previous installation" warnings prev
      in
        validate_file "experimental" warnings test
  in
    List.fold_left f warnings packages

exception CorruptRepository
exception CategoriesNotKnown of string list
exception PackagesNotKnown of string list

let select ((release, arch, timestamp, version, packages) : t) ?(inverse = false) ?(strip = false) categories required =
  let categories =
    List.fold_left (fun map name -> StringMap.add name false map) StringMap.empty categories in
  let required =
    List.fold_left (fun set name -> StringSet.add name set) StringSet.empty required in
  let test =
    if inverse
    then fun require belongs name ->
           not (StringSet.mem name required) && not (List.exists (fun name -> StringMap.mem name categories) belongs) || StringSet.mem name require
    else fun require belongs name ->
           StringSet.mem name required || StringSet.mem name require || List.exists (fun name -> StringMap.mem name categories) belongs
  in
  let (output, selected, map, require, categories, required) =
    let f (output, selected, map, require, categories, required) ((name, (belongs, sdesc, ldesc, curr, _, _)) as package) =
      let categories =
        let f categories name =
          if StringMap.mem name categories then
            StringMap.add name true categories
          else
            categories
        in
          List.fold_left f categories belongs
      in
        if test require belongs name then
          match curr with
            Some ({requires; _} as curr) ->
              (*
               * It is necessary to do this first, since some Cygwin packages depend on themselves!
               *)
              let selected = StringSet.add name selected in
              let f require package =
                if StringSet.mem package selected then
                  require
                else
                  StringSet.add package require in
              let package =
                if strip
                then (name, (belongs, sdesc, ldesc, Some {curr with source = None}, None, None))
                else package
              in
                (package::output, selected, map, List.fold_left f (StringSet.remove name require) requires, categories, StringSet.remove name required)
          | None ->
              raise CorruptRepository
        else
          (output, selected, StringMap.add name package map, require, categories, StringSet.remove name required)
    in
      List.fold_left f ([], StringSet.empty, StringMap.empty, StringSet.empty, categories, required) packages
  in
    if StringSet.is_empty required then
      let missing =
        StringMap.fold (fun name found acc -> if found then acc else name::acc) categories [] in
      if missing = [] then
        let rec f output selected require =
          match require with
            name::require ->
              begin
                try
                  let ((_, (categories, sdesc, ldesc, curr, _, _)) as package) = StringMap.find name map in
                    match curr with
                      Some ({requires; _} as curr) ->
                        let require =
                          let f require name =
                            if StringSet.mem name selected then
                              require
                            else
                              name::require
                          in
                            List.fold_left f require requires
                        and package =
                          if strip
                          then (name, (categories, sdesc, ldesc, Some {curr with source = None}, None, None))
                          else package
                        in
                          f (package::output) (StringSet.add name selected) require
                    | None ->
                        raise CorruptRepository
                with Not_found ->
                  f output selected require
              end
          | [] ->
              output
        in
          (release, arch, timestamp, version, f output selected (StringSet.elements require))
      else
        raise (CategoriesNotKnown missing)
    else
      raise (PackagesNotKnown (StringSet.elements required))

let string_of_repo ((release, arch, timestamp, version, packages) : t) =
  let buffer = Buffer.create (750 * List.length packages)
  in
    let write_key f name value =
      Buffer.add_string buffer (Printf.sprintf "%s: %s\n" name (f value))
    and string_of_release = function
      Cygwin -> "cygwin"
    and string_of_arch = function
      X86 -> "x86"
    | X86_64 -> "x86_64"
    and id x = x
    and may_string f = function 
      "" ->
        ()
    | value ->
        f value
    and may_list f = function
      [] ->
        ()
    | value ->
        f value
    and cyg_escape s = Printf.sprintf "\"%s\"" s
    and space_list lst = String.concat " " lst
    and file (name, size, checksum) =
      let f () = function
        MD5Sum sum
      | SHA512Sum sum
      | Base64URL sum ->
          sum
      in
        Printf.sprintf "%s %Ld %a" name size f checksum
    and cyg_message (key, msg) = Printf.sprintf "%s \"%s\"" key msg
    in
      Option.may (write_key string_of_release "release") release;
      Option.may (write_key string_of_arch "arch") arch;
      Option.may (write_key (Printf.sprintf "%.0f") "setup-timestamp") timestamp;
      Option.may (write_key id "setup-version") version;
      let write_package (name, (categories, sdesc, ldesc, curr, prev, test)) =
        let write_version header {version; requires; install; source; message} =
          if header <> ""
          then Buffer.add_string buffer header;
          may_list (write_key space_list "requires") requires;
          write_key id "version" version;
          Option.may (write_key file "install") install;
          Option.may (write_key file "source") source;
          Option.may (write_key cyg_message "message") message
        in
          Printf.bprintf buffer "\n@ %s\n" name;
          may_string (write_key cyg_escape "sdesc") sdesc;
          may_string (write_key cyg_escape "ldesc") ldesc;
          may_list (write_key space_list "category") categories;
          Option.may (write_version "") curr;
          Option.may (write_version "[prev]\n") prev;
          Option.may (write_version "[test]\n") test
      in
        List.iter write_package packages;
        Buffer.contents buffer

let append_slash item =
  let l = String.length item
  in
    if l = 0
    then invalid_arg "download_repository: invalid mirror"
    else if item.[l - 1] = '/'
         then item
         else item ^ "/"

let parse_mirrors data =
  let lines = ExtString.String.nsplit data "\n"
  and parse acc line =
    let line = String.trim line
    in
      if line = ""
      then acc
      else let (entry, region, country) =
             match ExtString.String.nsplit line ";" with
               [url; host; region; country] ->
                 ((append_slash url, host), region, country)
             | _ ->
                 raise CorruptRepository
           and updateMap key entry map =
             let current =
               try
                 StringMap.find key map
               with Not_found -> []
             in
               StringMap.add key (entry::current) map
           in
             updateMap "" entry (updateMap region entry (updateMap (region ^ "/" ^ country) entry acc))
  in
    List.fold_left parse StringMap.empty lines

let mirrors_url = "http://cygwin.com/mirrors.lst"

let setup_url = function
  X86 ->
    "http://cygwin.com/setup-x86.exe"
| X86_64 ->
    "http://cygwin.com/setup-x86_64.exe"

let ini_path = function
  X86 ->
    "x86/setup.ini"
| X86_64 ->
    "x86_64/setup.ini"

let download ?(ch = stderr) ?(show_msg = true) url =
  let msg =
    if show_msg
    then Printf.sprintf "Retrieving %s: " url
    else ""
  in
    Printf.fprintf ch "%s%!" msg;
    let buffer = Buffer.create 16384
    and errorBuffer = ref ""
    and connection = Curl.init ()
    and data buffer data =
      Buffer.add_string buffer data;
      String.length data
    and progress msg downloadTotal downloadSoFar _ _ =
      let _ =
        if downloadTotal > 0.
        then let msg' =
               Printf.sprintf "%.0f%%" (downloadSoFar /. downloadTotal *. 100.)
             in
               if msg' <> !msg
               then begin
                      Printf.fprintf ch "%s%s%!" (String.make (String.length !msg) '\b') msg';
                      msg := msg'
                    end
      in
        false
    and statusMsg = ref ""
    in
      Curl.set_errorbuffer connection errorBuffer;
      Curl.set_writefunction connection (data buffer);
      Curl.set_progressfunction connection (progress statusMsg);
      Curl.set_noprogress connection false;
      Curl.set_followlocation connection true;
      Curl.set_url connection url;
      Curl.perform connection;
      let l = String.length !statusMsg + String.length msg
      in
        let b = String.make l '\b'
        in
          Printf.fprintf ch "%s%s%s%!" b (String.make l ' ') b;
          let result =
            (Buffer.contents buffer, Curl.get_responsecode connection)
          in
            Curl.cleanup connection;
            result

(* @@DRA Not needed in opam *)
let do_mkdir dir =
  let rec f acc dir =
    if Sys.file_exists dir
    then let f acc dir =
           let acc' = Filename.concat acc dir
           in
             Unix.mkdir acc' 0o775;
             acc'
         in
           ignore (List.fold_left f dir acc)
    else f ((Filename.basename dir)::acc) (Filename.dirname dir)
  in
    f [] dir

let download_repository mirrors ((release, arch, timestamp, version, packages) : t) destination =
  let mirrors =
    if mirrors = []
    then invalid_arg "download_repository: no mirrors specified"
    else List.map append_slash mirrors
  and display_file_count () n =
    let suffix =
      if n = 1
      then ""
      else "s"
    in
      Printf.sprintf "%d file%s" n suffix
  and display_size () size =
    if size >= 1048576L
    then Printf.sprintf "%.0fMiB" (Int64.to_float size /. 1048576.)
    else if size >= 1024L
         then Printf.sprintf "%.0fKiB" (Int64.to_float size /. 1024.)
         else let suffix =
                if size = 1L
                then ""
                else "s"
              in
                Printf.sprintf "%Ld byte%s" size suffix
  in
    let files =
      let f acc (name, (_, _, _, curr, prev, test)) =
        let process acc = function
          Some {source; install; _} ->
            let acc =
              Option.map_default (fun elt -> elt::acc) acc install
            in
              Option.map_default (fun elt -> elt::acc) acc source
        | None ->
            acc
        in
          process (process (process acc curr) prev) test
      in
        List.fold_left f [] packages
    and download_file msg (remain, remain_size) (file, size, checksum) =
      let retries = 2
      and fsize = Int64.to_float size
      and target =
        let target = Filename.concat destination file
        in
          do_mkdir (Filename.dirname target);
          target
      and msg_stamp = ref 0.
      and msg_count = ref 0
      in
        let update_msg ?(force = false) msg' =
          let f msg' =
            let old = !msg
            in
              if old <> msg' && (force || Unix.gettimeofday () -. !msg_stamp > 0.1)
              then let l_msg' = String.length msg'
                   and l_msg = String.length old
                   in
                     let left_common =
                       let l = min l_msg l_msg'
                       in
                         let rec f n =
                           if n < l
                           then if old.[n] = msg'.[n]
                                then f (succ n)
                                else n
                           else n
                         in
                           f 0
                     in
                       let erase = l_msg - left_common
                       and erase_after = max 0 (l_msg - l_msg')
                       in
                         Printf.eprintf "%s%s%s%s%!" (String.make erase '\b') (String.sub msg' left_common (l_msg' - left_common)) (String.make erase_after ' ') (String.make erase_after '\b');
                         msg_stamp := Unix.gettimeofday ();
                         if force
                         then msg_count := 0
                         else incr msg_count;
                         msg := msg'
          in
            Printf.ksprintf f msg'
        in
          update_msg ~force:true "Downloading repository (%a; %a remain): " display_file_count remain display_size remain_size;
          begin
            let try_mirror base_msg update_sum init_sum finalise_sum =
              let rec try_mirror n offset ctx ch = function
                mirror::other_mirrors when n >= 0 ->
                  let url = mirror ^ file
                  in
                    let base_msg =
                      update_msg ~force:true "%s%s " base_msg url;
                      !msg
                    in
                      let rec attempt_download n offset ch =
                        if n >= 0
                        then let connection = Curl.init ()
                             and errorBuffer = ref ""
                             and check_size = ref true
                             and written = ref offset
                             in
                               let rec write data =
                                 if !check_size
                                 then begin
                                        check_size := false;
                                        if Int64.add offset (Int64.of_float (Curl.get_contentlengthdownload connection)) = size
                                        then write data
                                        else -1
                                      end
                                 else begin
                                        output_string ch data;
                                        update_sum ctx data;
                                        let l = String.length data
                                        in
                                          let c = Int64.add !written (Int64.of_int l)
                                          and spinner = [| '|'; '/'; '-'; '\\' |]
                                          in
                                            update_msg "%s%.0f%% %c" base_msg (Int64.to_float c /. fsize *. 100.) spinner.(!msg_count mod 4);
                                            written := c;
                                            l
                                      end
                               in
                                 Curl.set_errorbuffer connection errorBuffer;
                                 Curl.set_writefunction connection write;
                                 Curl.set_resumefromlarge connection offset;
                                 Curl.set_followlocation connection true;
                                 Curl.set_url connection url;
                                 let () =
                                   try
                                     Curl.perform connection;
                                     update_msg ~force:true "%s" base_msg
                                   with Curl.CurlException (code, n, name) ->
                                     Curl.cleanup connection;
                                     attempt_download (pred n) !written ch
                                 in
                                   let code = Curl.get_responsecode connection
                                   in
                                     Curl.cleanup connection;
                                     if code = 200 || code = 226
                                     then if !written = size
                                          then if finalise_sum ctx = checksum
                                               then close_out ch
                                               else attempt_download (pred n) 0L (close_out ch; open_ch ())
                                         else attempt_download (pred n) 0L (close_out ch; open_ch ())
                                     else attempt_download (pred n) 0L (close_out ch; open_ch ())
                        else try_mirror retries offset ctx ch other_mirrors
                      in
                        attempt_download n offset ch
              | _::mirrors ->
                  try_mirror retries offset ctx ch mirrors
              | [] ->
                  raise Not_found (* @@DRA This is the wrong exception - fatal error *)
              and open_ch () =
                let ch = open_out target
                in
                  set_binary_mode_out ch true;
                  ch
              in
                try_mirror retries 0L (init_sum ()) (open_ch ())
            in
              match checksum with
                SHA512Sum _ ->
                  try_mirror !msg Sha512.update_string Sha512.init (fun ctx -> SHA512Sum (Sha512.to_hex (Sha512.finalize ctx))) mirrors
              | Base64URL _ ->
                  (* Not implemented *)
                  assert false
              | MD5Sum _ ->
                  (*
                   * Legacy - Cygwin doesn't use MD5's any more, so it isn't a concern that this is inefficient
                   *)
                  try_mirror !msg (fun _ _ -> ()) (fun _ -> ()) (fun _ -> MD5Sum (Digest.file target)) mirrors
          end;
          (pred remain, Int64.sub remain_size size)
    in
      let (n, size) =
        List.fold_left (fun (n, size) (_, size', _) -> (succ n, Int64.add size size')) (0, 0L) files
      in
        let msg = ref ""
        in
          let _ = List.fold_left (download_file msg) (n, size) files
          in
            let msg' =
              Printf.sprintf "Download complete! (%a downloaded for %a)" display_size size display_file_count n
            and msg = !msg
            in
              Printf.eprintf "%s%s%s\n%!" (String.make (String.length msg) '\b') msg' (String.make (max (String.length msg - String.length msg') 0) ' ')

let _ =
  Curl.global_init Curl.CURLINIT_GLOBALSSL;
  at_exit (fun _ -> Curl.global_cleanup ())
