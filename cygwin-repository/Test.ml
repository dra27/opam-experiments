(*
 * Download the mirrors file, pick a random one, download the setup.exe, and build the repository
 *)

module StringMap = Map.Make(String)

let write_file data file =
  CygRepository.do_mkdir (Filename.dirname file);
  let ch = open_out file
  in
    set_binary_mode_out ch true;
    output_string ch data;
    close_out ch

let _ =
  Random.self_init ();
  let (mirrors, code) =
    CygRepository.download CygRepository.mirrors_url
  in
    CygRepository.do_mkdir "cygrepo";
    let mirrors =
      let mirrors =
        List.map fst (StringMap.find "Europe/UK" (CygRepository.parse_mirrors mirrors))
      in
        (* @@DRA This means a mirror is included twice, but we don't care for now... *)
        (List.nth mirrors (Random.int (List.length mirrors)))::mirrors
    in
      let (setup, code) = CygRepository.download (CygRepository.setup_url CygRepository.X86)
      in
        write_file setup "cygrepo\\setup-x86.exe";
        let ini_path = CygRepository.ini_path CygRepository.X86
        in
          let (ini, code) = CygRepository.download (List.hd mirrors ^ ini_path)
          in
            let repo = CygParser.parse CygLexer.token (Lexing.from_string ini)
            and categories = (*["Base"]*) ["_obsolete"]
            and packages = [(*"git"; "openssh"; "make"; "mingw64-i686-gcc-core"; "mingw64-x86_64-gcc-core"; "m4"; "patch"; "unzip"*)]
            in
              let repo = CygRepository.select repo ~inverse:true ~strip:true categories packages
              in
                let issues = CygRepository.is_valid repo in
                if issues <> []
                then Printf.eprintf "This repository has some issues:\n  %s\n%!" (String.concat "\n  " issues);
                write_file (CygRepository.string_of_repo repo) (Filename.concat "cygrepo\\files" ini_path);
                try
                  CygRepository.download_repository mirrors repo "cygrepo\\files"
                with Curl.CurlException (e, i, s) ->
                  Printf.eprintf "CurlException:\n  %s\n  %d\n  %S\n%!" (Curl.strerror e) i s
