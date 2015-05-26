%%%==============================================================================
%%% File    : mim_ct_rest_handler.erl
%%% Author  : Piotr Nosek <piotr.nosek@erlang-solutions.com>
%%% Description : Rest handler simulating authentication REST API
%%% Created : 6 Aug 2014 by <piotr.nosek@erlang-solutions.com>
%%%==============================================================================

-module(mim_ct_roster_handler).

-behaviour(cowboy_http_handler).

% cowboy_http_handler exports
-export([init/3, handle/2, terminate/3]).

-define(BASIC_AUTH, <<"softkitty:purrpurrpurr">>).

%%% -------------------------------------------
%%% Cowboy callbacks
%%% -------------------------------------------

init(_Type, Req, _Opts) ->
    {Path, Req2} = cowboy_req:path(Req),
    {Method, Req3} = cowboy_req:method(Req2),
    {RestMethod, Req4} = cowboy_req:binding(method, Req3),
    {<<"Basic ", AuthHeader/binary>>, Req5} = cowboy_req:header(<<"authorization">>,
                                                                Req4, <<"Basic ">>),
    IsAuthorized = base64:decode(AuthHeader) == ?BASIC_AUTH,
    {KV, ReqFinal} = case Method of
                          <<"GET">> ->
                              cowboy_req:qs_vals(Req5);
                          <<"POST">> ->
                              {ok, BodyKV, Req6} = cowboy_req:body_qs(Req5),
                              {BodyKV, Req6}
                      end,
    {_, User} = lists:keyfind(<<"user">>, 1, KV),
    {_, Server} = lists:keyfind(<<"server">>, 1, KV),
    {_, Pass} = lists:keyfind(<<"pass">>, 1, KV),
    USP = {User, Server, Pass},
    {ok, ReqFinal, {Method, Path, RestMethod, USP, mim_ct_rest:consume_fail(), IsAuthorized}}.

handle(Req, {_, _, _, _, _, false} = State) ->
    Req1 = cowboy_req:set_resp_header(<<"www-authenticate">>, <<"Basic realm=\"MIM\"">>, Req),
    reply(Req1, State, 401, "401 Unauthorized");
handle(Req, {_, _, _, _, true, _} = State) ->
    reply(Req, State, 404, "");
handle(Req, {<<"GET">>, <<"/roster/", FromJID/binary>>, Unknown, {U, S, P}, _, _} = State) ->
    io:format("unknown: ~p~n", [Unknown]),
    io:format("FromJID: ~p~n", [FromJID]),
    JSON = "{}",
    reply(Req, State, 200, list_to_binary(JSON));
handle(Req, {<<"GET">>, <<"/auth/", _/binary>>, <<"check_password">>, {U, S, P}, _, _} = State) ->
    Result = mim_ct_rest:check_password(U, S, P),
    reply(Req, State, 200, list_to_binary(atom_to_list(Result)));
handle(Req, {<<"GET">>, <<"/auth/", _/binary>>, <<"get_password">>, {U, S, _P}, _, _} = State) ->
    case mim_ct_rest:get_password(U, S) of
        false ->
            reply(Req, State, 404, <<>>);
        Password ->
            reply(Req, State, 200, Password)
    end;
handle(Req, {<<"GET">>, <<"/auth/", _/binary>>, <<"user_exists">>, {U, S, _P}, _, _} = State) ->
    Result = mim_ct_rest:user_exists(U, S),
    reply(Req, State, 200, list_to_binary(atom_to_list(Result)));
handle(Req, {<<"POST">>, <<"/auth/", _/binary>>, <<"set_password">>, {U, S, P}, _, _} = State) ->
    ok = mim_ct_rest:set_password(U, S, P),
    reply(Req, State, 204, <<>>);
handle(Req, {<<"POST">>, <<"/auth/", _/binary>>, <<"remove_user">>, {U, S, _P}, _, _} = State) ->
    Code = remove_to_code(mim_ct_rest:remove_user(U, S)),
    reply(Req, State, Code, <<>>);
handle(Req, {<<"POST">>, <<"/auth/", _/binary>>, <<"remove_user_validate">>, {U, S, P}, _, _} = State) ->
    Code = remove_to_code(mim_ct_rest:remove_user_validate(U, S, P)),
    reply(Req, State, Code, <<>>);
handle(Req, {<<"POST">>, <<"/auth/", _/binary>>, <<"register">>, {U, S, P}, _, _} = State) ->
    Code = case mim_ct_rest:register(U, S, P) of
               ok -> 201;
               conflict -> 409
           end,
    reply(Req, State, Code, <<>>);
handle(Req, State) ->
    mim_ct_rest:op({invalid_request, State}),
    {ok, Req2} = cowboy_req:reply(404, [{<<"content-type">>, <<"text/plain">>}],
                                  io_lib:format("Unknown request: ~p", [State]), Req),
    {ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
    ok.

%%% -------------------------------------------
%%% Internal functions
%%% -------------------------------------------

reply(Req, State, Code, Payload) ->
    {ok, Req2} = cowboy_req:reply(Code, [], Payload, Req),
    {ok, Req2, State}.

remove_to_code(not_found) -> 404;
remove_to_code(not_allowed) -> 403;
remove_to_code(ok) -> 204.
