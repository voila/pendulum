
open Pendulum.Runtime_ast

let dummyatom () = Format.printf "Hello\n"

let%sync mouse_machine1 =
  input s;
  let s' = !!s + 1 in
  let s'' = !!s' + 1 in
  (loop (pause))


let%sync incr =
  input s;
  input s2;
  emit s (!!s + 1 + !!s2);
  atom (Format.printf "%d" !!s)

let%sync m_loop_incr =
  input zz;
  let s1 = 5 in
  let s2 = 5 in
  loop (
    run incr (s2, s1);
    pause
  )
  ||
  loop (
    run incr (s1, s2);
    pause
  )

let%sync many_par =
  loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause
  || loop pause



let%sync reactive_player =
  input play;
  input pause;
  input start_slide;
  input stop_slide;
  input media_time;
  input media;
  input slider;

  let cant_update = () in
  loop begin
    present play (atom (print_string "play"));
    present pause (atom (print_string "pause"));
    pause
  end
  || loop begin
    await start_slide;
    trap t' (loop (
        emit cant_update ();
        present stop_slide (
          atom (print_string "stop_slide");
          exit t');
        pause)
      );
    pause
  end
  ||
  loop begin present cant_update nothing
      (present media_time (atom(
           print_string "media_time"
         ))); pause
  end



let%sync reactive_player =
  loop begin
    trap t (
      loop (pause); pause
    );
  end



let%sync bang =
  loop begin
    !(Format.printf "lol");
    pause
  end

let%sync testexpr =
  input iinp;

  loop begin
    present (iinp & !!iinp)
      !(Format.printf "lol");
    pause
  end

let%sync parall_present_pause =
  let s = () in
  (present s (pause) nothing;
   !(print_string "42-1"))
  ||
  (present s (pause) nothing;
   !(print_string "42-2"))

let%sync emit_basic0 elt0 elt1 elt2 =
  input (elt3 : int), (elt4 : int), elt5;
  input (elt6 : int), (elt7 : int), elt8;
  loop pause


let%sync gatherer_0 =
  input s (fun acc s -> s + acc);
  input s2 (fun acc s -> s :: acc) ;
  loop begin
    emit s 1;
    emit s2 1;
    pause
  end
  ||
  loop begin
    present s !(Format.printf "s %d" !!s);
    pause
  end

let () =
  let set_s, set_s2, r = gatherer_0 (0, []) in
  set_s 1;
  set_s 1;
  set_s2 1;

  ignore @@ r ()





