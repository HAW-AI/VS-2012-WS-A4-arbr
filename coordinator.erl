-module(coordinator).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).

-behaviour(gen_server).
% tasks
% - start datasource
% - start receiver
% - start sender
% - manage slots

-define(?SENDPORT,14010).

-record(state, {datasourcePID, receiverPID, senderPID}).

start(RecPort,Station,MulticastIP)->
	gen_server:start(?MODUL,[RecPort,?SENDPORT,Team,Station,MulticastIP],[]).

init([RecPort,SendPort,Station,MulticastIP])->
	
	