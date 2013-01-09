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

-define(SENDPORT,14010).

-record(state, {datasourcePID, receiverPID, senderPID, sendport, recport}).

start(RecPort,Station,MulticastIP,LocalIP)->
	gen_server:start(?MODULE,[RecPort,?SENDPORT,Station,MulticastIP,LocalIP],[]).

init([RecPort,SendPort,Station,MulticastIP,LocalIP])->
	{ok,DatasourcePID} = datasource:start(),
	
	%http://erldocs.com/R15B/kernel/gen_udp.html
	%http://erldocs.com/R15B/kernel/inet.html#setopts/2
	%http://stackoverflow.com/questions/78826/erlang-multicast
	{ok,RecSocket} = gen_udp:open(RecPort,[
										   binary,inet,
										   {multicast_loop, true},
										   {add_membership,{MulticastIP,LocalIP}}]
								 ),
	{ok,SendSocket} = gen_udp:open(SendPort,[
											 binary,
											 inet,
											 {multicast_loop, true},
											 {add_membership,{MulticastIP,LocalIP}}]
								  ),
	
	{ok,ReceiverPID} = receiver:start(self(),RecSocket),
	{ok,SenderPID} = sender:start(self(),SendSocket,MulticastIP,RecPort),
	
	{ok, #state{datasourcePID=DatasourcePID,
				receiverPID=ReceiverPID,
				senderPID=SenderPID,
				sendport=SendPort,
				recport=RecPort}}.

handle_cast({datasink, Data},State)->
	log("Neue Nachricht empfangen: ~p",[Data]);

%TODO: Slotberechnung
handle_cast({recieved, Timestamp, Packet},State)->
	ok.


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
	