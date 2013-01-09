-module(util).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).
-import(werkzeug, [logging/2]).

log(File, Message) -> log(File, Message, []).
log(File, Message, Data) ->
  logging(File, io_lib:format("[~s] (~p) "++Message++"~n",[timestamp_log(),self()]++Data)).

timestamp_log() ->
  {Year, Month, Day} = date(),
  {Hour, Minute, Second} = time(),
  lists:flatten(
    io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w",[Year, Month, Day, Hour, Minute, Second])
  )++","++millisec().

millisec() ->
  {_, _, MicroSec} = now(),
  string:substr( float_to_list(MicroSec/ 1000000), 3, 3).

timestamp() ->
  {MegaSecs, Secs, MicroSecs} = now(), % would erlang:timestamp() also work? i'm unsure
  (MegaSecs * math:pow(10,9)) * (Secs * math:pow(10,3)) * (MicroSecs div 1000).
