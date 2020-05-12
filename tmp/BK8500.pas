unit BK8500;


{$IFDEF FPC}  //for compatibility between delphi  and lazarus
{$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils, SynAser, Windows, StdCtrls, Dialogs,
  myutils;


Var
 BKdebug:boolean;  //DEBUG!!!!!!!!!!!

//TODO: monitor status
{

OverV: boolean;
OverC: boolean;
OverP: boolean;
OverTemp: boolean;
IsON: boolean;
RemoteSense: boolean;
ReversedVoltage: boolean;
}




type TBK8500message = record
   data: array[0..25] of byte;
   len: byte;
   end;

    TBKMode = (CBKCC, CBKCV, CBKCR, CBKCP);
    TBKFunction = (CBKFixed,  CBKShort, CBKTransient, CBKList, CBKBattery);

type TConnectStatus = ( CDisconn, CConnecting, CBusy, CReady, CError );

TBKStatus = record
   OutputOn: boolean;
   Mode: TBKMode;
   Func: TBKFunction;
   //from status reg
   Calculating: boolean;
   WaitingForTrigger: boolean;
   RemoteIsOn: boolean;
   LocalKeyOn: boolean;
   RemSensingIsON: boolean;
   TimerIsON: boolean;
   ReversedVoltage: boolean;
   OverV: boolean;
   OverC: boolean;
   OverP: boolean;
   OverTemp: boolean;
   IsCC: boolean;
   IsCV: boolean;
   IsCP: boolean;
   IsCR: boolean;
   NotRemoteConnect: boolean;
   Lastreg1: byte;
   Lastreg2: word;
end;


TBK8500Control = class(TObject)
{
 == intermediate object for communication with BK8500 load
 call SetIniParams after inicialization
}
public
  function BKOpen(): boolean;
  procedure BKClose();
  procedure TurnONOFF( enabled: boolean);
  procedure setRemote();
  procedure ReadUIStatus;
  procedure SetConstC(setp: double);
  procedure SetConstV(setp: double); {setp: voltage in V}
  procedure SetIniParams();
  procedure GetExtendedState();
private
  //
  //BKLastProcCode: boolean;
public
  ConStatus: TConnectStatus;
  //last result
  LastU: double;
  LastI: double;
  LastP: double;
  LastValid : boolean;
  LastTimestamp : double;  //now()
  BKStatus: TBKSTatus;
  LastCmdOK: boolean;
  //config
  SerialPortDevice: string;
  port: string;
  baud: longint;
  databits: byte;
  parity: char;
  stopbits: byte;
end;


//---error reporting and logging fucntion
//-----------------------------------------------
procedure BKReportError(errlvl: byte; msg: string);


// --- general utils
function BitIsSet(w: longint; bitnr: byte): boolean;


//---low level helper function --
function BKcalcchecksum(Var r: Tbk8500message): byte;
function BKcheckcommand(Var r: Tbk8500message): boolean;
function BKCmdtostring( Var cmd: Tbk8500message ): string;
procedure BKPrepareEmptyCmd(Var cmd: Tbk8500message; addr:byte=0); {  sets first byte, address to 0, and emty all other bytes}
procedure BKFinishCmd(Var cmd: Tbk8500message);
procedure BKNumberTo4Bytes( n: longint; Var a, b, c, d: byte );
procedure BK4BytesToNumber(a, b, c, d: byte; Var n: longint);
procedure BKDecodeVal4ByteFromCmd( Var cmd: Tbk8500message; offs: byte; Var n: longint);
//
function BKsendcmd( Var cmd: Tbk8500message ): boolean;
function BKgetResult( Var res: Tbk8500message; Var rescode: integer ): boolean;
//For get CPU Tick  - for mneassuring time
function GetCPUTick(): Int64;







Implementation

uses Math;


//---- private variables declaration

Var
   Serial1 : TBlockSerial;

    BKlastcmd: Tbk8500message;
    BKlastResult: Tbk8500message;
    BKConnected: boolean;
    BKlastOK: boolean;
    BKlastResCode: integer;
    BKlastErrorMsg: string;

    BKDebugfile: text;


//*************************



procedure BKReportError(errlvl: byte; msg: string);
begin
   //TODO:!!!!
  //ShowMessage(msg);
end;










//-----------

function BKcalcchecksum(Var r: Tbk8500message): byte;
Var i: integer;
    s: longint;
begin
  s:=0;
  for i:=0 to 24 do s:= s + r.data[i];
  s := s mod 256;
  Result := s;
end;

function BKcheckcommand(Var r: Tbk8500message): boolean;
Var
   chksum: byte;
begin
  chksum := BKcalcchecksum( r);
  Result := False;
  if (chksum = r.data[25]) and (r.data[0]=$AA) then Result := True;
end;

procedure BKPrepareEmptyCmd(Var cmd: Tbk8500message; addr:byte=0);
  {  sets first byte, address to 0, and emty all other bytes}
Var i:integer;
begin
  with cmd do
    begin
         data[0] := $AA;
         data[1] := addr;
         for i:=2 to 25 do data[i] := 0;
         len := 26;
    end;
end;

procedure BKFinishCmd(Var cmd: Tbk8500message);
{fills in checksum}
begin
  cmd.data[25]:= BKcalcchecksum( cmd );
end;


function BinaryStrTostring( a: AnsiString ): string;
Var
    c: byte;
    i, ll: longint;
    s, s1: string;
begin
  s := '';
  ll := length(a);
  for i:=0 to ll-1 do
  begin
    c := ord(a[i]);
    s1 := IntToHex( c, 2 );
    if c = 0 then s1 := '..';
    s := s + s1 + ' ';
  end;
  Result := s;
end;

function BKCmdtostring( Var cmd: Tbk8500message ): string;
Var
    c: byte;
    i, ll: longint;
    s, s1: string;
begin
  s := '';
  ll := cmd.len;
  if ll>26 then ll := 26;
  for i:=0 to ll-1 do
  begin
    c := cmd.data[i];
    s1 := IntToHex( c, 2 );
    if c = 0 then s1 := '..';
    s := s + s1 + ' ';
  end;
  Result := s;
end;


procedure BKNumberTo4Bytes( n: longint; Var a, b, c, d: byte );
{a is lowest byte}
begin
  a := n mod 256;
  b := (n shr 8) mod 256;
  c := (n shr 16) mod 256;
  d := (n shr 24) mod 256;
end;

procedure BK4BytesToNumber(a, b, c, d: byte; Var n: longint);
{a is lowest byte}
begin
  n := d;
  n := n*256 + c;
  n := n*256 + b;
  n := n*256 + a;
end;

procedure BKDecodeVal4ByteFromCmd( Var cmd: Tbk8500message; offs: byte; Var n: longint);
begin
  n := 0;
  if (offs>cmd.len - 4) then
  begin
    offs := 0;
    BKReportError(0, 'BKDecodeVal4ByteFromCmd / offs>cmd.len - 4');
    exit;
  end;
  BK4BytesToNumber(cmd.data[offs], cmd.data[offs+1], cmd.data[offs+2], cmd.data[offs+3], n);
end;


//**************
//low level functions
//


function BKsendcmd( Var cmd: Tbk8500message ): boolean;
Var
  a: string[26];
  i: byte;
begin
  BKlastcmd := cmd;
  setlength(a, 26);
  for i:=0 to 25 do a[i+1] := chr( cmd.data[i] );
  Serial1.Purge;
  Serial1.SendString(a);
  Serial1.Flush();
  BKLastOK := (Serial1.LastError = 0);
  Result := BKLastOK;
end;


function BKReceiveNchars( N: word; maxtime: longint): Ansistring;
{repeatedly reads from serial port with small timeout, until N chars received or
maximum time (maxtime) in miliseconds elapsed}
Const
  Cminitimeout = 5;
  CBufMAX = 255;
var
  i, j, xn : longint;
  a, a1: Ansistring;
  waiting,len:integer;
  buff: array[0..CBufMAX] of char;

begin
 a := '';
 xn := maxtime div Cminitimeout;
 for i:=1 to xn do
 begin
  // modified 8.7.2014
   waiting := Serial1.WaitingData;
   setlength(a1, 0);
  if (waiting > 0) then
     begin  // pull data in from comm buffer
     //len := RawBuffSize - raw.inpos;
     if ( N < waiting) then   // if too big for my fifo then
         waiting := N;       // reduce to fit just the end of buffer this time
     if (waiting >= CBufMAX ) then waiting := CBufMAX - 1;
     //len := Serial1.RecvBuffer(@Raw.Buff[raw.inpos], waiting);

     //a1 := Serial1.RecvBufferStr(waiting, Cminitimeout);
     //
     len := Serial1.RecvBuffer(@buff[0], waiting);
     setlength(a1, len);
     for j:=1 to len do
       begin
         a1[j] := buff[j-1];
       end;
     end
  else
     delayMS(Cminitimeout);
   //

   if BKDebug then
     begin
      Append(BKdebugfile);
      Writeln(BKdebugfile, 'recv: in round '+IntToStr(i) +' was ' + inttostr(length(a1)) + 'chars: "'+ BinaryStrTostring(a1) +'"' );
      Closefile(BKdebugfile);
     end;

   a := a + a1;
   N := N - length(a1);
   if (N <= 0) then break;
 end;
 waiting := Serial1.WaitingData;
 if waiting>0 then Serial1.RecvBuffer(@buff[0], waiting);
 Result := a;
end;

function BKgetResult( Var res: Tbk8500message; Var rescode: integer ): boolean;
{ parses return string - if the result was ok then returns true
in the "Res" this value is returned  -1=other error, 0=OK, 1= ...., 2= ...
}
Var
    i, len: integer;
    icmd, code: byte;
    r: string;
    a: Ansistring;
begin
  Result := false;
  rescode := -1;
  BKLastResCode := -1;

  a := BKReceiveNchars(26, 900);
  Serial1.Purge;
  len :=  length(a);
  if len>26 then  len:=26;
  r := a;

  for i:=0 to len-1 do res.data[i] := ord (r[i+1]) ;
  for i:= len to 25 do res.data[i] := 0;
  res.len := len;

  if len <> 26 then
  begin
    //Memo1.Lines.Add('error rcv');
     //MessageDlg('Exiting the Delphi application.', mtInformation,   [mbOk], 0);
    Result:= False;
    exit;
  end;

  if not BKcheckcommand(res) then
   begin
   //ShowMessage('checksum failed');
     Result:= False; exit;
   end;
  BKlastResult := res;

  Result := true;
  BKLastResCode := rescode;
end;


{
TODO !!!!!!!!!!!!!!!!!!!!!!!
icmd := res.data[2];
  if icmd <> $12 then
   begin
     ShowMessage('icmd not $12');
     Result:= False; exit;
     end;
  //TODO:
  code := res.data[3];
  if code = $80 then rescode := 0
  else
  begin
   ShowMessage('code not $80');
    rescode := 1;
  end;
}





function BitIsSet(w: longint; bitnr: byte): boolean;
Var
 x,y: longint;
begin
  x := 1 shl bitnr;
  Result := (w and x) > 0;
end;



// ----------------------------------
// TBK8500Control

function TBK8500Control.BKopen: boolean;
begin
  BKConnected := false;
  Result := false;
  ConStatus := CDisconn;
  Serial1 := TBlockSerial.Create;
  if BKDebug then
    begin
      //Serial1.RaiseExcept:=true;
    end;
  //connect
  //try
    if length(SerialPortDevice) = 0 then  SerialPortDevice :=  'COM13';

    Serial1.LinuxLock := false;
    Serial1.Connect( SerialPortDevice );
      //Serial1.DTR := true;   // For compatibility with VC820-style of connection
  //example: Serial1.Config(ConstsBaud[FBaudRate],
  //                ConstsBits[FDataBits],
  //                ConstsParity[FParity],
  //                ConstsStopBits[FStopBits],
  //                FSoftflow, FHardflow);

  if Serial1.LastError <> 0 then
    begin
      Result := false;
      ShowMessage('fail open');
      BKReportError(0, 'Serial conn  fail on: open');
      exit;
      end;

    databits := 8;
    parity := 'N';
    stopbits := 0;   //0=1stop 2=1.5stop b 2=2stop b

    if (baud=0) then baud := 9600;
    //if (databits=0) then databits := 8;
    //if (ord(parity)=0) then parity := 'N';



    Serial1.Config(baud, databits, parity, stopbits, false, false);
    Serial1.DTR := true;
    Serial1.RTS := false;

    //Serial1.Config(9600, 8, 'N', 0, false, false);

  //except
   //    on E : Exception do begin
    //     ShowMessage(E.ClassName + ' error raised, with message : ' + E.Message);
     //  end;
     //end;

  if Serial1.LastError <> 0 then
    begin
      Result := false;
      ShowMessage('fail config');
      BKReportError(0, 'Serial conn  fail on: config rs232');
      exit;
    end;

  BKConnected := true;
  ConStatus := CReady;

  //debug
  if BKDebug then
   begin
     AssignFile(BKdebugfile, 'bk8500-tmp-dump.txt');
     if not FileExists( 'bk8500-tmp-dump.txt' ) then
     begin
       Rewrite(BKdebugfile);
       Close(BKdebugfile);
     end;
   end;

   Result := true;
   //ShowMessage('yes');
end;



procedure TBK8500Control.BKclose();
begin
  if BKconnected then Serial1.CloseSocket;
  BKconnected := false;
end;


//////////////////////////////
{higher level commands...}
////////////////////////////////

procedure TBK8500Control.SetRemote();
Var
    cmd, res: Tbk8500message;
    b, b2: boolean;
    rcode: integer;
begin
  BKLastOK := true;
  BKPrepareEmptyCmd( cmd );
  cmd.data[2] := $20;
  cmd.data[3] := $01;
  BKFinishCmd( cmd );
  //
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  if (not B) or (not b2)then BKLastOK := false;
  LastCmdOK := BKLastOK;
end;


procedure TBK8500Control.ReadUIStatus();
Var
    cmd, resu: Tbk8500message;
    b, b2: boolean;
    rcode: integer;
    v: longint;
    reg1: byte;
    reg2: word;
    VV : double;
    BK_TimeOfSending2, BK_TimeOfRecieving2: cardinal;
    BK_TimeOfSending, BK_TimeOfRecieving : Int64;
begin
  BKLastOK := true;
  //read display - 0x5F
  BK_TimeOfSending2 := GetTickCount();
  BK_TimeOfSending := GetCPUTick();
  BKPrepareEmptyCmd( cmd );
  cmd.data[2] := $5F;
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( resu, rcode);
  BK_TimeOfRecieving2 := GetTickCount();
  BK_TimeOfRecieving := GetCPUTick();

  //ShowMEssage( 'b ' + BoolToStr(b) + ' b2 ' + BoolToStr(b2));

  if (not B) or (not b2)then BKLastOK := false;


  //tmp debug - write cmd to file
  if BKDebug then
  begin
    Append(BKdebugfile);
    Writeln(BKdebugfile, DateTimeToStr(Now) + ' (ReadUI):' );
    Writeln(BKdebugfile, BKCmdtostring(cmd) );
    Writeln(BKdebugfile, BKCmdtostring(resu) );
    Writeln(BKdebugfile, 'Elasped time for response: ', IntToStr(BK_TimeOfRecieving-BK_TimeOfSending));
    Writeln(BKdebugfile, 'Elasped time for response: ', IntToStr(BK_TimeOfRecieving2-BK_TimeOfSending2));
    Writeln(BKdebugfile, '');
    Close(BKdebugfile);
  end;
  //
  //parse result
  LastU:=0;
  LastI:=0;
  LastP:=0;
  LastValid := false;
  //ShowMEssage( BoolToStr(bklastok) );
  if BKLastOK then begin
    LastValid := true;
    LastTimestamp := now();
    //if rcode<>0 then exit;
    //getU    offs := 3;
    BKDecodeVal4ByteFromCmd(resu, 3, v);
    VV := v;  //in mV
    LastU := VV / 1000; //in V
    //getI   offs:=7;
    BKDecodeVal4ByteFromCmd(resu, 7, v);
    VV := v;  //in 0.1mA
    LastI := VV / 10000; //in A
    //getP  offs:=11;
    BKDecodeVal4ByteFromCmd(resu, 11, v);
    VV := v;  //in 1mW
    LastP := VV / 1000; //in W
  end else begin
    LastU:=NaN;
    LastI:=NaN;
    LastP:=NaN;
    LastValid := false;
  end;
  //status registers
  reg1 :=  resu.data[15];
  reg2 :=  resu.data[16] + resu.data[17] * 256;
  BKStatus.Lastreg1 := reg1;
  BKStatus.Lastreg2 := reg2;
  //???????????!!!!!!!!!!!!!!!!!!!! TODO
      { status bytes (from 0x5F):
       ---------------
        Bit Meaning
      0 Calculate the new demarcation coefficient
      1 Waiting for a trigger signal
      2 Remote control state (1 means enabled)
      3 Output state (1 means ON)
      4 Local key state (0 means not enabled, 1 means enabled)
      5 Remote sensing mode (1 means enabled)
      6 LOAD ON timer is enabled
      7 Reserved
      The demand state register's bit meanings are:
      Bit Meaning
      0 Reversed voltage is at instrument's terminals (1 means yes)
      1 Over voltage (1 means yes)
      2 Over current (1 means yes)
      3 Over power (1 means yes)
      4 Over temperature (1 means yes)
      5 Not connect remote terminal
      6 Constant current
      7 Constant voltage
      8 Constant power
      9 Constant resistance }

  with BKStatus do
     begin
     //status reg 1
       Calculating := BitIsSet(reg1, 0);
       WaitingForTrigger := BitIsSet(reg1, 1);
       RemoteIsOn := BitIsSet(reg1, 2);
       OutputOn := BitIsSet(reg1, 3);
       LocalKeyOn := BitIsSet(reg1, 4);
       RemSensingIsON :=  BitIsSet(reg1, 5);
       TimerisON := BitIsSet(reg1, 6);
      //status reg 2
      ReversedVoltage := BitIsSet(reg2, 0);
      OverV := BitIsSet(reg2, 1);
      OverC := BitIsSet(reg2, 2);
      OVerP := BitIsSet(reg2, 3);
      OverTemp := BitIsSet(reg2, 4);
      NotRemoteConnect := BitIsSet(reg2, 5);
      IsCC := BitIsSet(reg2, 6);
      IsCV := BitIsSet(reg2, 7);
      IsCP := BitIsSet(reg2, 8);
      IsCR := BitIsSet(reg2, 9);
     end;

  //debug
  //Writeln(ft, '  '+FloatToStr(BKLastU) + ' V ' + FloatToStr(BKLastI) + ' A ' + FloatToStr(BKLastP) + ' W ');
  //Writeln(ft, '');
  //close(ft);
  //


  //LastValid := true;
  LastCmdOK := BKlastOK;
end;


procedure TBK8500Control.SetConstC(setp: double);
{curr: current in A}
Var
    i: integer;
    offs: byte;
    cmd, res: Tbk8500message;
    b, b2: boolean;
    rcode: integer;
    v: longint;
    reg1: byte;
    reg2: word;
    errcntsent, errcntrecv: integer;
begin
  BKLastOK := true;
  errcntsent := 0;
  errcntrecv := 0;
  //check that remote is on
  if not BKstatus.RemoteIsOn then
  begin
    setRemote;
    //TODO:
  end;

  //set CC setpoint
  {
3 Lower low byte of current. 1 represents 0.1 mA.
4 Lower high byte of current.
5 Upper low byte of current.
6 Upper high byte of current.}

  v := trunc( abs( setp ) * 10000);
  BKPrepareEmptyCmd( cmd );
  with cmd do
    begin
    data[2] := $2A;
    offs := 3;
    BKNumberTo4Bytes( v, data[offs], data[offs+1], data[offs+2], data[offs+3] );
    end;
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  //tmp debug - write cmd to file
  if BKDebug then
  begin
    Append(BKdebugfile);
    Writeln(BKdebugfile, DateTimeToStr(Now) + ' (set CC setp : '+ IntToStr(v) + '):' );
    Writeln(BKdebugfile, BKCmdtostring(cmd) );
    Writeln(BKdebugfile, BKCmdtostring(res) );
    Writeln(BKdebugfile, '');
    Close(BKdebugfile);
  end;
  //part 2: set CC mode
  BKPrepareEmptyCmd( cmd );
  cmd.data[2] := $28;
  cmd.data[3] := 0;  //CC mode
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  //tmp debug - write cmd to file
  if BKDebug then
  begin
    Append(BKdebugfile);
    Writeln(BKdebugfile, DateTimeToStr(Now) + ' (set CC' );
    Writeln(BKdebugfile, BKCmdtostring(cmd) );
    Writeln(BKdebugfile, BKCmdtostring(res) );
    Writeln(BKdebugfile, '');
    Close(BKdebugfile);
  end;
  if (errcntsent>0) or (errcntrecv>0) then BKLastOK := false;
  LastCmdOK := BKLastOK;
end;


procedure TBK8500Control.SetConstV(setp: double);
{setp: voltage in V}
Var
    i: integer;
    cmd, res: Tbk8500message;
    b, b2: boolean;
    rcode: integer;
    v: longint;
    offs: byte;
    errcntsent, errcntrecv: integer;
begin
  BKLastOK := true;
  errcntsent := 0;
  errcntrecv := 0;
  //check that remote is on
  if not BKstatus.RemoteIsOn then
  begin
    setRemote;
    //TODO:
  end;
  //step 1: set CV setpoint
  {
  3 Lower low byte of voltage. 1 represents 1 mV.
  4 Lower high byte of voltage.
  5 Upper low byte of voltage.
  6 Upper high byte of voltage.
  }
  v := trunc( abs( setp ) * 1000);
  BKPrepareEmptyCmd( cmd );
  with cmd do
    begin
    data[2] := $2C;
    offs := 3;
    BKNumberTo4Bytes( v, data[offs], data[offs+1], data[offs+2], data[offs+3] );
    end;
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  //tmp debug - write cmd to file
  if BKDebug then
  begin
    Append(BKdebugfile);
    Writeln(BKdebugfile, DateTimeToStr(Now) + ' (set CV setp : '+ IntToStr(v) + '):' );
    Writeln(BKdebugfile, BKCmdtostring(cmd) );
    Writeln(BKdebugfile, BKCmdtostring(res) );
    Writeln(BKdebugfile, '');
    Close(BKdebugfile);
  end;
  //step 2: set CV mode
  BKPrepareEmptyCmd( cmd );
  cmd.data[2] := $28;
  cmd.data[3] := 1;  //CV mode
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  //tmp debug - write cmd to file
  if BKDebug then
  begin
    Append(BKdebugfile);
    Writeln(BKdebugfile, DateTimeToStr(Now) + ' (set CV)' );
    Writeln(BKdebugfile, BKCmdtostring(cmd) );
    Writeln(BKdebugfile, BKCmdtostring(res) );
    Writeln(BKdebugfile, '');
    Close(BKdebugfile);
  end;
  if (errcntsent>0) or (errcntrecv>0) then BKLastOK := false;
  LastCmdOK := BKLastOK;
end;


{procedure TBK8500Control.SetConstV(setp: double);
//setp: voltage in V
Var
    i: integer;
    cmd, res: Tbk8500message;
    b, b2: boolean;
    rcode: integer;
    v: longint;
    offs: byte;
    reg1: byte;
    reg2: word;
    errcntsent, errcntrecv: integer;
begin
  BKLastOK := true;
  errcntsent := 0;
  errcntrecv := 0;
  //step 1: set CV setpoint
  //
  //3 Lower low byte of voltage. 1 represents 1 mV.
  //4 Lower high byte of voltage.
  //5 Upper low byte of voltage.
  //6 Upper high byte of voltage.
  //
  v := trunc( abs( setp ) * 1000);
  BKPrepareEmptyCmd( cmd );
  with cmd do
    begin
    data[2] := $2C;
    offs := 3;
    BKNumberTo4Bytes( v, data[offs], data[offs+1], data[offs+2], data[offs+3] );
    end;
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  //tmp debug - write cmd to file
  if BKDebug then
  begin
    Append(BKdebugfile);
    Writeln(BKdebugfile, DateTimeToStr(Now) + ' (set CV setp : '+ IntToStr(v) + '):' );
    Writeln(BKdebugfile, BKCmdtostring(cmd) );
    Writeln(BKdebugfile, BKCmdtostring(res) );
    Writeln(BKdebugfile, '');
    Close(BKdebugfile);
  end;
  //step 2: set CV mode
  BKPrepareEmptyCmd( cmd );
  cmd.data[2] := $28;
  cmd.data[3] := 1;  //CV mode
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  //tmp debug - write cmd to file
  if BKDebug then
  begin
    Append(BKdebugfile);
    Writeln(BKdebugfile, DateTimeToStr(Now) + ' (set CV)' );
    Writeln(BKdebugfile, BKCmdtostring(cmd) );
    Writeln(BKdebugfile, BKCmdtostring(res) );
    Writeln(BKdebugfile, '');
    Close(BKdebugfile);
  end;
  if (errcntsent>0) or (errcntrecv>0) then BKLastOK := false;
  LastCmdOK := BKLastOK;
end;
}

procedure TBK8500Control.TurnONOFF( enabled: boolean);
{enabled: 1 = laod ON 0 = load OFF}
Var
    cmd, res: Tbk8500message;
    b, b2: boolean;
    rcode: integer;
    v: longint;
    reg1: byte;
    reg2: word;
begin
  //check that remote is on
  if not BKstatus.RemoteIsOn then
  begin
    setRemote;
    //TODO:
  end;
  BKLastOK := true;
  BKPrepareEmptyCmd( cmd );
  cmd.data[2] := $21;
  if enabled then cmd.data[3] := 1  //1 is ON
         else cmd.data[3] := 0;  //OFF
  BKFinishCmd( cmd );
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  if (not B) or (not b2)then BKLastOK := false;
  LastCmdOK := BKLastOK;
end;



//procedure BKReadStatus();
{ 0x5E Get function type (FIXED/SHORT/TRAN/LIST/BATTERY)
0x5F Read input voltage, current, power and relative state
Byte
0x29 Read the mode being used (CC, CV, CW, or CR)
}
{ 0x5E Get function type (FIXED/SHORT/TRAN/LIST/BATTERY)
0x5F Read input voltage, current, power and relative state
Byte
0x29 Read the mode being used (CC, CV, CW, or CR)
}
//begin
//end;




procedure TBK8500Control.SetIniParams();
{sends configuration commands to default state
  ...that is:    ...
0x22 Set the maximum voltage allowed
0x24 Set the maximum current allowed
0x26 Set the maximum power allowed
  Set CC mode current  ... to zero
0x28 Set CC, CV, CW, or CR mode  ... CC mode
0x32 Set CC mode transient current and timing  ??? disable transient
0x52 Disable/enable timer for LOAD ON
0x56 Enable/disable remote sensing   ... disable
 ...
0x5D Select FIXED/SHORT/TRAN/LIST/BATTERY function !!!!!!!  set to FIXED
}
Var
    i: integer;
    cmd, res: Tbk8500message;
    b, b2: boolean;
    rcode: integer;
    v: longint;
    offs: byte;
    reg1: byte;
    reg2: word;
    errcntsent, errcntrecv, errcnt3: integer;
begin
  BKLastOK := True;
  errcntsent := 0;
  errcntrecv := 0;
  errcnt3 := 0;
  //0a set remote mode
  SetRemote();
  if not BKLastOK then Inc(errcnt3);
  //
  //0b set load OFF
  TurnONOFF( false );
  if not BKLastOK then Inc(errcnt3);
  //
  //1) set fixed mode    $5D
  BKPrepareEmptyCmd(cmd); //sets first byte, address to 0, and emty all other bytes
  cmd.data[2] := $5D;
  cmd.data[3] := 0;
  BKFinishCmd(cmd);
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  if not b then Inc(errcntsent);
  if not b2 then Inc(errcntrecv);
  //
  //2) set max current to 10A
  //
  BKPrepareEmptyCmd(cmd);
  cmd.data[2] := $24;
  v := 100000;
  with cmd do
     begin
     offs := 3;
     BKNumberTo4Bytes( v, data[offs], data[offs+1], data[offs+2], data[offs+3] );
     end;
  BKFinishCmd(cmd);
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  if not b then Inc(errcntsent);
  if not b2 then Inc(errcntrecv);
  //
  //3) set max voltage to 15V
  //
  BKPrepareEmptyCmd(cmd);
  cmd.data[2] := $22;
  v := 15000;
  with cmd do
     begin
     offs := 3;
     BKNumberTo4Bytes( v, data[offs], data[offs+1], data[offs+2], data[offs+3] );
     end;
  BKFinishCmd(cmd);
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  if not b then Inc(errcntsent);
  if not b2 then Inc(errcntrecv);
  //
  //4) disable timer
  //
  BKPrepareEmptyCmd(cmd);
  cmd.data[2] := $52;
  cmd.data[3] := 0;
  BKFinishCmd(cmd);
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  if not b then Inc(errcntsent);
  if not b2 then Inc(errcntrecv);
  //
  //5) ENABLE remote sensing
  //
  BKPrepareEmptyCmd(cmd);
  cmd.data[2] := $56;
  cmd.data[3] := 1;    //TODO:!!!!!!!!!!!!!!!!!!
  BKFinishCmd(cmd);
  b := BKsendcmd(cmd);
  b2 := BKgetResult( res, rcode);
  if not b then Inc(errcntsent);
  if not b2 then Inc(errcntrecv);
  //
  //6) set CC and current to zero
  //
  SetConstC(0);
  if not BKLastOK then Inc(errcnt3);
  if (errcntsent>0) or (errcntrecv>0) or (errcnt3>0) then BKLastOK := false;
  LastCmdOK := BKLastOK;
end;


procedure TBK8500Control.GetExtendedState();
{sends configuration commands to default state
...that is:    ...
0x5E Get function type (FIXED/SHORT/TRAN/LIST/BATTERY)
0x5F Read input voltage, current, power and relative state
0x6A Get product's model, serial number, and firmware version
0x59 Read trigger source
0x57 Read the state of remote sensing
0x53 Read timer state for LOAD ON
//0x4F Read minimum voltage in battery testing
//0x35 Read CV mode transient parameters
//0x33 Read CC mode transient parameters
0x2D Read CV mode voltage
0x2B Read CC mode current
0x29 Read the mode being used (CC, CV, CW, or CR)
0x25 Read the maximum current allowed
0x23 Read the maximum voltage allowed
}
begin

end;



function GetCPUTick(): Int64;
asm
   DB $0F,$31 // this is RDTSC command. Assembler, built in Delphi, 
              // does not support it,
              // that is why one needs to overcome this obstacle.
end;




end.
