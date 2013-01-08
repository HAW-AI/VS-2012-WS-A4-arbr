-module(util).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).
-import(werkzeug, [logging/2]).

log(File, Message) -> log(File, Message, []).
log(File, Message, Data) ->
  logging(File, io_lib:format("[~s] (~p) "++Message++"~n",[timestamp(),self()]++Data)).

timestamp() ->
  {Year, Month, Day} = date(),
  {Hour, Minute, Second} = time(),
  lists:flatten(
    io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w",[Year, Month, Day, Hour, Minute, Second])
  )++","++millisec().

millisec() ->
  {_, _, MicroSec} = now(),
  string:substr( float_to_list(MicroSec/ 1000000), 3, 3).
