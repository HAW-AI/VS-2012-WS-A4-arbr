-module(coordinator).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).

-behaviour(gen_server).
-import(util, [log/2]).
% tasks
% - start datasource
% - start receiver
% - start sender
% - manage slots

-define(?SENDPORT,14010).

-record(state, {datasourcePID, receiverPID, senderPID, sendport, recport}).

start(RecPort,Station,MulticastIP)->
	gen_server:start(?MODUL,[RecPort,?SENDPORT,Team,Station,MulticastIP],[]).

init([RecPort,SendPort,Station,MulticastIP])->
	{ok,DatasourcePID} = datasource:start(),
	
	%http://erldocs.com/R15B/kernel/gen_udp.html
	%http://erldocs.com/R15B/kernel/inet.html#setopts/2
	{ok,RecSocket} = gen_udp:open(RecPort,[binary,inet,{broadcast,true}]),
	{ok,SendSocket} = gen_udp:open(SendPort,[binary,inet,{broadcast,true}]),
	
	{ok, #state{datasourcePID=DatasourcePID,
				sendport=SendPort,
				recport=RecPort}.

terminate(normal,State)->
	gen_server:cast(State#state.datasourcePID,{stop}),
	gen_server:cast(State#state.receiverPID,{stop}),
	gen_fsm:cast(State#state.senderPID,{stop}),
	ok.
	


log(Message) ->
	util:log("Coordinator.log",Message).

%% durch gen_server vorgegeben
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_info(_Info, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
	