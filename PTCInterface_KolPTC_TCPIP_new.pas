unit PTCInterface_KolPTC_TCPIP_new;


{

Range: 0=sn�mac� odpor 10mOhm, 15A, 1=odpor 1 Ohm, cca do 100mA
Feedback: softwarov� feedback, od nuly postupne V2, V4, VRef, I, Ix10, IuA, 255=Direct Output
Setpoint: pro sw feedback
OutputEnabled: pripopoj� nebo odpoj� v�stup (ovl�d� rel�)
}

//comment the define, if you do not have the libraries and want to compile without KolPTC!!!!!
{$DEFINE PTCDLL}


{$IFDEF FPC}  //for compatibility between delphi  and lazarus
{$mode delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils, StdCtrls, Dialogs,
  TlHelp32, PSAPI,
  myutils, Logger, ConfigManager, FormGlobalConfig,
  HWAbstractDevicesV3,  MyParseUtils, StrUtils,
  Ptc_defines,
  MyTCPClientForKolServer, MyContainers, MyPSUtils_winapi, MVConversion;

{create descendant of virtual abstract potentio object and define its methods
especially including definition of configuration and setup methods}

Const
  CKolPtcIfaceVer = 'KolPTC Interface TCPIP v3';
  CKolPtcIfaceVerLong = CKolPtcIfaceVer + '(by Michal Vaclavu 2017)';

  CConfigSection = 'KolPTCInterface';

  CDebug = false; //true; //false; //true;

  CMaxBufferSize = 256;
  CKolPTCStaticArraySize = 10;

Type

  TStaticArrayOfDouble = array[0..CKolPTCStaticArraySize-1] of double;
  TStaticArrayOfSingle = array[0..CKolPTCStaticArraySize-1] of single;

  TKolPTCFeedback = (CPTCFbV2, CPTCFbV4, CPTCFbVref, CPTCFbI, CPTCFbIx10, CPTCFbIuA, CPTCFbDO, CPTCFbUnknown);
  TKolPTCRange = (CPTCRng500mA, CPTCRng15A );


  TKolPTCRegisters = ( CRegUndef, CRegADC, CRegV4Range, CRegRelayON, CRegSetpoint, CRegSwFeedback,
                      CRegProtectStatus, CRegProtectCmd, CRegLimSafe, CRegLimHard, CRegMonIII, CRegCRC,
                      CRegLCDmsg, CRegIDProduct, CRegIDVendor, CRegIDVer, CRegIDstr1, CRegIDstr2, CRegFPLEDs, CRegSwitches, CRegAutocalib, CRegAutorange);
  TKolPTCChannels = ( CChV4, CChVref, CChV2, CChI, CChI10, CChSP );

  TKolPTCRegisterConfig = array [TKolPTCRegisters] of byte;
  TKolPTCChannelConfig = array [TKolPTCChannels] of byte;

  TKolBuffer = array of byte;
  TArrayOfDouble = array of double;

  TKolPTCChannelData = record
     //Ain: array of double;
     //Aout: array of double;
     //nAin: byte;
     //nAout: byte;
     V2: single;
     V4: single;
     Vref: single;
     I: single;
     Ix10: single;
     IuA: single;
     AC: single;
  end;

  TKolPTCStatus = record
     OutputOn: boolean;
     FuseStatusRaw: longint;
     Setpoint: double;
     FeedbackRaw: integer; //internal representation of TKolPTCFeedback - use conversion func
     RangeRaw: integer; //internal representation of TKolPTCRange  - use conversion func
     V4HardRng: TRangeRecord;
     V4SoftRng: TRangeRecord;
     HWFuseActive: boolean;
     SoftLimActive: boolean;
     VPout: single;
     VNout: single;
     IPout: single;
     INout: single;
     IP12: single;
     IN12: single;
  end;

  TKolPTCExtendedStatus = record
     RegADC: TStaticArrayOfDouble;
     RegADC_n: byte;
     RegRelayOn: byte;
     RegSetpoint: single;
     RegSwFeedback: byte;
     RegProtectStat: word;
     RegFuse_safe: TStaticArrayOfDouble;
     RegFuse_safe_n: byte;
     RegFuse_hard: TStaticArrayOfDouble;
     RegFuse_hard_n: byte;
     RegMonI: TStaticArrayOfDouble;
     RegMonI_n: byte;
     CRCstr: string;
     RegIdstr1: string;
     RegIdstr2: string;
     V4Range: TRangeRecord;
  end;

  TKolFuseRngLimitsRec = record
     V2rng: TRangeRecord;
     V4rng: TRangeRecord;
     Vrefrng: TRangeRecord;
     Irng: TRangeRecord;
  end;


  TKolPTCStateImage = record     //used to restore last state e.g. after restart of ptc control server
     OutputOn: boolean;
     Setpoint: double;
     Feedback: TKolPTCFeedback; //internal representation of TKolPTCFeedback - use conversion func
     IRange: TKolPTCRange; //internal representation of TKolPTCRange  - use conversion func
     LimitsSoft: TKolFuseRngLimitsRec;
     LimitsHard: TKolFuseRngLimitsRec;
     valid: boolean;
  end;




  TKolPTCObject = class (TPotentiostatObject)
    //WATCH OUT: if HW or SW fuse was triggered - user will need to correct the cause and call "Reset Fuse",
    //           fuse is signalled in the flag set
    public
      constructor Create; //Create(ifaceid: string);
      destructor Destroy; override;
    public
    //inherited virtual functions - must override!
      function AquireDataStatus(Var rec: TPotentioRec; Var Status: TPotentioStatus): boolean; override;
    //  returns electrical DATA and status
    //  this is the only fucntion that actualy aquires the status info (every time it is called)
    //  and after each call the internal status is updated and with it, also the corresponding flags if relevant!
    //  !!! range of voltage and current is checked (and flags set),
    //               but NO ACTION IS TAKEN to prevent overrange -> This should be done by HIGHER LEVEL control fucntion!!!!
      function SetCC( val: double): boolean; override;
      function SetCV( val: double): boolean; override;
      function TurnLoadON(): boolean; override;
      function TurnLoadOFF(): boolean; override;
    public
    //general control functions
      function IsAvailable(): boolean; override;        //indication that device is available = ready to be initialized (meaning can be communicated with)
                                                          //if false, it means the device cannot be initilized and cannot become ready
      function Initialize(): boolean; override;   //assuming the device is available and connected, try to set initial condition
                                                       //without initialization, the device should not become ready
      procedure Finalize; override;   //do tasks to  prepare for disconnecting
                                              // device will become not ready, if possible - object will disconnect the port beeing used for communication
      function GetFlags(): TPotentioFlagSet; override;   //flags may be device specific, example of common flag would be "Current Overrange" indicator
      function GetFuseMsg: string; override; //report last (HARD) FUSE error code and msg
      function ResetFuse: boolean; override; //recover from fuse event
    //
    public
      function GenFileInfoHeaderBasic: string; override;
      function GenFileInfoHeaderIncludeDC: string; override;
    private
    //iherited internal fields (for properties)
    //fName: string;
    //fDummy: boolean;
    //fReady: boolean;
    //fRngV4SWLimit: TRangeRecord;
    //fRngV4HardLimit: TRangeRecord;
    //fRngActCurr: TPotentioRangeRecord;
    //fRngActVolt: TPotentioRangeRecord;
    //fRngActCurrId: byte;
    //fRngActVoltId: byte;
    //fRngCurrCount: byte;
    //fRngVoltCount: byte;
  //RANGE reporting and control
    protected
      //procedure SetRngCurrent(nr: byte); virtual; abstract;
      //procedure SetRngVoltage(nr: byte); virtual; abstract;
      procedure SetRngV4SwLimit(rec: TRangeRecord); override;
      //procedure SetRngV4HardLimit(rec: TRangeRecord); virtual; abstract;
    public
      //HW specific features control methods
      function Connect(): boolean;  //Call to this to load DLL and assign control functions ... necessary to became availalble
      function SetResetFuseCmd(): boolean;
      function SetFeedback( fb: TKolPTCFeedback ): boolean;
      function SetRange( r: TKolPTCRange ): boolean;
      function SetSetpoint( sp: double ): boolean;
      function SetOutputRelay( enabled: boolean): boolean;

       //advanced HW specific status aquiring methods
       //all methods return true/false telling about result, data are passed by reference
 //     Function Ptc_IsConnected: boolean;
      function ReadPTCServer(Var chdata: TKolPTCChannelData; Var st: TKolPTCStatus): boolean;
      //function ReadChannels(Var chdata: TKolPTCChannelData): boolean; obsolete replaced by readptcserver
      //function ReadStatus(Var st: TKolPTCStatus): boolean;  //status inlcuding fuse status
      function ReadPTCStatusExtended(Var extst: TKolPTCEXtendedStatus): boolean;  //read maximum info status from PTC registers, including V4range
      function ReadFuseSoft(Var fuserec: TKolFuseRngLimitsRec): boolean;
      function ReadV4range(Var rrec: TPotentioRangeRecord): boolean;   //partially obsolete
      //general register access
      function ReadRegister(regnr: word; Var buf: TKolBuffer; Var retlen: word): boolean; //size is dynamic, adjustable, expect common size (max CBufMaxsize )
      function WriteRegister(regnr: word; Var bytes: ansistring  ): boolean;  //size is dynamic
      function ReadRegisterShift(regnr: word; shift: byte; Var buf: TKolBuffer; Var retlen: word): boolean; //size is dynamic, adjustable, expect common size (max CBufMaxsize ) //starts nit from beginning bu from byte "shift"
      function WriteRegisterShift(regnr: word; shift: byte; Var bytes: ansistring  ): boolean;  //size is dynamic
      function SetSafetyRangeV4(lowlim, highlim: double): boolean;
      function SetFuseSoftLimits(Var fuserec: TKolFuseRngLimitsRec): boolean;
      function ReadRegADC(Var ad: TArrayOfDouble): boolean;
      function ReadRegRelayOn(Var val: byte): boolean;
      function ReadRegSetpoint(Var val: single): boolean;
      function ReadRegSwFeedback(Var val: byte): boolean;
      function ReadRegProtectStatus(Var val: word): boolean;
      function ReadRegFwFuseHard(Var ad: TArrayOfDouble): boolean;
      function ReadRegFwFuseSoft(Var ad: TArrayOfDouble): boolean;
      function ReadRegMonI(Var ad: TArrayOfDouble): boolean;
      function ReadRegCRC(Var crc: string): boolean;
      function ReadRegLCDmsg(Var s: string): boolean;
      function ReadRegDeviceType(Var s: string ): boolean;
      function PingPTC(): boolean;   //sends echo request using PTCQuery
      //
      function GetInfo: boolean;
      function CheckAvailable(): boolean;   //tries communicate with server and sets fAvailable!! that is important to allow normal communication
      procedure MarkAsConfigured;  //should verify setup (registers)
      //
      function TCPSendUserCMD(cmd: string; Var reply: string; timeout: longint): boolean;
      function TCPSendReceive(cmd: string; Var reply: string; timeout: longint): boolean;
      function TCPSendCmdRetry(cmd: string; Var reply: string): boolean;
      function TCPIsEndOfMessage( reply: string ): boolean;
      //
      function TCPSendPtcQuery(Var bufin: TKolBuffer; Var bufout: TKolBuffer; Timeout: longint; Var PtcFlags: TPotentioFlagSet): boolean;  //using TCP PtcQuery command
      function TCPSendPtcQueryLowLevel(Var bufin: TKolBuffer; Var bufout: TKolBuffer): boolean;  //using TCP PtcQuery command
      function TCPSendGeneralPTCcmd(cmd: string; Var reply: string; Timeout: longint; Var PtcFlags: TPotentioFlagSet): boolean;  //response is "OK returnval"/ "NOK returnval"
      //
      function WaitForPTCPing(timeout: longint): boolean;
      function EncodeLowLevelCmdforTCP(Var buf: TKolBuffer): string;  //using TCP PtcQuery command
      function DecodeLowLevelCmdReply(Var rep: string; Var buf:TKolBuffer): boolean;
      procedure TCPDisconnect;
      procedure TCPTryReconnect;
      procedure TryResync;
      procedure DebugLogTurnOnTemporary;
    public
      EventQueuePTCServer: TMyStringQueueThreadSafe;
    private
      procedure HandlePTCEvent(eventstr: string);
    public
      function GetHWIdstr: string;  //returns dll/firmware version
    private
      //internal access lock control  and helper functions to check state before sending command
      kolPtcLock: boolean;  //for future - prevents multiple simultaneous call to PTC library
      function CheckConnectedLeaveMsg( where: string ): boolean;
      function LockAndCheckConnectedLeaveMsg( where: string ): boolean;
      function TryToLockIfNotLeaveMsg( where: string ): boolean;
      procedure Unlock;
    private            //internal configuration, stored into ini file
      fPTCVersion: integer;
      fTCPClient: TMyTCPClientForKolServer;
      fTCPconfigured: boolean;
      fTCPTimeout: longint;
      fConnectingLock : boolean;
      //
      fPTCFlags: TPotentioFlagSet;
      //
      fTCPLastTRYConnectDateTime: TDateTime;
      //
      fLog: TLoggerThreadSafeNew; //fLog:  TMyLoggerThreadSafe;
      //
      fConfClient: TConfigCLient;

      //
      fFormatSettings:  TFormatSettings;   //internal default format used
      fRegConfig: TKolPTCRegisterConfig;
      fDefRegConfig: TKolPTCRegisterConfig;
      fRegVersionID: string;  //to verify that the firmaware has same version as the internal config is meant to be used with
      fChannelConfig: TKolPTCChannelConfig;
      //fAutoSwitchRng: boolean;
      fRetryCount: byte;
      fBufferedRead: boolean;
      fConstUFeedback: TKolPTCFeedback; //in internal KolPTC representation - when switch to Ufeedback, use this one
      fConstIFeedback: TKolPTCFeedback; //in internal KolPTC representation - when switch to Ifeedback, use this one
      fV4SafetyRange: TPotentioRangeRecord;
      fV4SafeRegOffset: byte;
      fFuseProtectUseOldStyle: boolean;
      fRegWriteEnabled: boolean;  //do not write into registers, until the firmware version has been checked!!!!
      //
      fPTC1_IchannelWorkaround: boolean;
      fUseVrefInsteadOfV4: boolean;
      //config load save methods
    private
      //configuration and initialization
      fRegConfigured: boolean;  //because of different versions of HW - first register numbers should be initialized and this flag marked
      //fAvailable: boolean;
      fTryingConnectionFlag: boolean;
      fidcmd: longword;
      fTCPhost: string;  //config
      fTCPport: string;  //config
      fProtocolVer: byte;

    private
      //kolPTC info object
      fPtcInfo: TPtcInfo;
    public
      //configuration and initialization
      procedure LoadConfig;
      procedure SaveConfig;
      procedure InitRegConfigWithDef(Var RegConf: TKolPTCRegisterConfig );
      function KolRegisterToStr(r: TKolPTCRegisters ): string;      
      procedure ConfigureTCPIP( host, port: string);
      //procedure AssignConfigManager( Var cm: TLoadSaveConfigManager );  //use this to partially automate storing/loading of configuration from PTC control form
      //
      procedure SetupRegConfig( r: TKolPTCRegisters; val: byte );
      procedure SetupChannelConfig( ch: TKolPTCChannels; val: byte );
    public
      //conversion functions
      function InternalFBToKol(i: integer ): TKolPTCFeedback;
      function InternalRngToKol(i: integer ): TKolPTCRange;
      function KolFBToStr( fb:TKolPTCFeedback ): string;
      function KolRangetoStr(r: TKolPTCRange): string;
    private
      //low level communication
      //function Ptc_SendCmdarray( Var ab: array of byte; alen: byte ): boolean;
      //function Ptc_SendCmdWrapper( s: string ): boolean;
    private
      // internal more extended use
      function SetCCx( val: double; forceturnon: boolean = false; forcechangefb: boolean = false): boolean;
      function SetCVx( val: double; forceturnon: boolean = false; forcechangefb: boolean = false): boolean;
      //helper conversion fucntions
      function FBtoInternal(fb:TKolPTCFeedback): integer;
      function RangeToInternal(r: TKolPTCRange): integer;
      function FBtoMode(fb:TKolPTCFeedback): TPotentioMode;
      function KolRngToRngRec( kr: TKolPTCRange): TPotentioRangeRecord;
      //
      procedure setPTCdebug(b: boolean);
      procedure LeaveLogMsg(a: string);   //in order to do it THREAD SAFE. must call logmsg using Synchronize!!!!!!
      procedure DebugLeaveLogMsg(a: string; force: boolean = false); //check debug flag and if set logs string!!!!
      procedure kolMsg(s: string); //set lastmsg and log it at the same time
      procedure kolErrorMsg(s: string); //set lastmsg and log it at the same time
      function kolAssert(ex: boolean; s: string): boolean; //if ex is FALSE leaves warning message; returns true if Assert OK
      //
      //rubbish TODO
      function GetDataBuffered(Var Rec: TPotentioRec; Var Status: TPotentioStatus): boolean;
      procedure WaitForSetpointCurr;
      function DecreaseCurrent(): boolean;
      //
    private
      fFlagSet: TPotentioFlagSet;
      //more stuff
      fPTCdebug: boolean;  //DEBUG!!!!!!!!!!! for more info messages
      flastOCV: double;
      //!!!!DESIRED PTC state - this is kept updated after each set call - need it to reliable restore state e.g. after fuse event
      fPTCDesiredState: TKolPTCStateImage;
      //last known data and parametrs from PTC
      fLastPTCdata: TPotentioRec;
      fLastPTCStatus: TPotentioStatus;
      fLastKolPtcStatus: TKolPTCStatus;
      fPTCIdString: string;
      //fLastKolPtcExtStatus: TKolPTCExtendedStatus;
      //fLastChannelData: TKolPTCChannelData;
      //error counters
      fCommCntTotal: longint;
      fCommErrCorrectedCnt: longint;
      fCommErrNotCorrCnt: longint;
      //
      fTemporarydebugOn: boolean;
      fTemporaryDebugOffTime: longword;
      //
      fPTCServerPID: cardinal;
      fPTCServerHProcess: cardinal;
      fPTCServerStartedHere: boolean;
      fptcsrvwindname: string;
      fPTCSrvExeName: string;
      //
      fRequestRestartServer: boolean;
      fNextPingTICKTime: longword;
      fPTCServerRestartEnabled: boolean;
      //
      fSavedPTCState: TKolPTCStateImage;
      //
      fPTCServerIsOnLocalhost: boolean;
      fPTCServerAppPath: string;
      fPTCServerDefaultAppPath: string;
    public
      function GetPTCServerPID: longword;
      function GetPTCServerAppPath: string;
      function StartPTCServer(): boolean;
      function KillPTCServer(): boolean;
      function MakeSureServerRunsOrStartIt: boolean;
      function IsPTCServerRunning: boolean;
      procedure WaitForTCPServerStart(toutMS: longint=1000);
      procedure WaitForTCPClientConnect(toutMS: longint=10000);
      procedure WaitForPing(toutMS: longint=10000);      
      procedure RestartPTCServer;
      procedure SaveLastState;
      procedure RestoreLastState;
      //
    private
      procedure WriteRetryCount( c: byte );   //make sure c is at least 1
    public
      //exported properties
      property IsTCPConfigured: boolean read fTCPConfigured;
      property IsRegConfigured: boolean read fRegConfigured;
      //
      property ConfigRegisters: TKolPTCRegisterConfig read fRegConfig;
      property ConfigChannels: TKolPTCChannelConfig read fChannelConfig;
      property BufferedRead: boolean read fBufferedRead write fBufferedRead;
      property LastOCV: double read FLastOCV;
      property DebugEnabled: boolean read fPTCdebug write  setPTCdebug;
      property Flags: TPotentioFlagSet read fFlagSet;
      //
      property CommCntTotal: longint read fCommCntTotal;
      property CommCntErrCorrected: longint read fCommErrCorrectedCnt;
      property CommCntErrNotCorr: longint read fCommErrNotCorrCnt;
      //
      property ConstUFeedback: TKolPTCFeedback read fConstUFeedback write fConstUFeedback;
      property ConstIFeedback: TKolPTCFeedback read fConstIFeedback write fConstIFeedback;
      property RetryCount : byte read fRetryCount write WriteRetryCount;
      property FWVersionCRC: string read fRegVersionID write fRegVersionID;
      //property AutoSwitchRng: boolean read fAutoSwitchRng write fAutoSwitchRng;
      property UseVrefInsteadOfV4: boolean read fUseVrefInsteadOfV4  write fUseVrefInsteadOfV4;

      //
      property RequestRestartServer: boolean read fRequestRestartServer write fRequestRestartServer;
      property RestartServerEnabled: boolean read fPTCServerRestartEnabled;

      //
      property PTCServerIsOnLocalhost: boolean read fPTCServerIsOnLocalhost write  fPTCServerIsOnLocalhost;
      property PTCServerPID: longword read fPTCServerPID;
      property PTCServerAppPath: string read  fPTCServerAppPath;
  end; //*************************



Type

TVarType = (CVarInt, CVarFloat, CVarBool, CVarString, CVarArray, CVarPointer);

TArgRecord = record
               pa: Pointer;
               atype: TVarType;
             end;

TArgArray = array of TArgRecord;

TBoolFunc = function(): boolean;
PBoolFunc = ^TBoolFunc;


function RetryCallUntilOK( Pfn: PBoolFunc; argc: byte; ArgArray: TArgArray; retryc: byte): boolean;
//pfn: pointer to function that returns boolean (interface functions inptc.dll)
//tries to repeat call until geting true as result- in order to overcome communication errors and so


//function KolFBToStr( fb:TKolPTCFeedback ): string;
//function KolRangetoStr(r: TKolPTCRange): string;

function kolbuftostr(Var buf: TKolBuffer ): string;


function MyXStrToInt( val: string): longint;


function processKol1Byte( Var kbuf: TKolBuffer; Var klen: word; Var res: byte): boolean;
function processKolU16LE( Var kbuf: TKolBuffer; Var klen: word; Var res: word): boolean;
function processKolArrayOfDouble( Var kbuf: TKolBuffer; Var klen: word; Var ad: TArrayOfDouble): boolean;


procedure InitWithNAN( Var rec: TKolFuseRngLimitsRec); overload;


procedure CopyDynArrayToStatic( Var adyn: TArrayOfDouble; Var astat: TStaticArrayOfDouble; Var statlen: byte);

Implementation

uses Math, DateUtils, Windows, MyTCPClient;



const
    PTC_DLL_Name = 'Ptc.dll';


//usage of external functions in PTC.DLL
{
 SAFE is to call anytime only "ptc_isconnected"!!!
 until at least 10.10.2015: if not connecetd, calling other function causes undefined state and errors (memory leaks and so on)
}


{
PTC setup details
  Range: 0=sn�mac� odpor 10mOhm, 15A, 1=odpor 1 Ohm, cca do 100mA
  Feedback: softwarov� feedback, od nuly postupne V2, V4, VRef, I, Ix10
}

Const
    CKolPTCRangeR10mOhm = 0;
    CKolPTCRangeR1Ohm = 1;

    CKolPTCFeedbackV2 = 0;
    CKolPTCFeedbackV4 = 1;
    CKolPTCFeedbackVRef = 2;
    CKolPTCFeedbackI = 3;
    CKolPTCFeedbackIx10 = 4;
    CKolPTCFeedbackIuA = 5;
    CKolPTCFeedbackDO = 255;

//----------------------------

constructor TKolPTCObject.Create;  //Create(ifaceid: string);
begin
  inherited Create('Kolibrik.net Potentiostat', CKolPtcIfaceVer, false);
  //basic prop ini
  fPTCIdString := 'Unknown';
  InitRegConfigWithDef( fRegConfig );
  //special proeprties ini
  fRegVersionID := 'NULL';
  fRegWriteEnabled := false;
  fRegConfigured := false;
  //fAvailable := false;
  fTCPconfigured := false;
  fidcmd := 1000;
  fPTC1_IchannelWorkaround := false;
  fUseVrefInsteadOfV4 := false;
  //fnumeric ormat
  GetLocaleFormatSettings(0, fFormatSettings);
  fFormatSettings.DecimalSeparator := '.';
  //default configuratio
  fRetryCount := 2;
  fTCPhost := 'localhost';
  fTCPport := '20006';
  fTCPConfigured := false;
  fPTCVersion := 0; //default old version
  fTryingConnectionFlag := false;
  fConstUFeedback := CPTCFbV4;
  fConstIFeedback := CPTCFbI;
  // init config object
  fConfClient := TConfigClient.Create( GlobalConfig.ConfigServerHW, CConfigSection);
  //init dynamic arrays
  //
  fLog := TLoggerThreadSafeNew.Create;
  if fLog<>nil then fLog.StartLogFilePrefix('!ptc-tcpip-log_','.txt');
  //tcp client
  fTCPClient := TMyTCPClientForKolServer.Create;
  fTCPClient.AssignLogProc( LeaveLogMsg );
  fTCPClient.RegisterEventHandler( HandlePTCEvent );
  fTCPTimeout := 4000;
  //
  fPTCServerPID := 0;
  fPTCServerHProcess := 0;
  fPTCServerAppPath := '';

  fTemporarydebugOn := false;
  //
  fRequestRestartServer := false;
  fConnectingLock := false;
  //
  fPTCServerStartedHere := false;
  fNextPingTICKTime := 0;
  fTCPLastTRYConnectDateTime := 0;
  //
  with fPTCDesiredState do
  begin
    OutputOn := false;
    Setpoint := 0;
    Feedback := CPTCFbI;
    IRange := CPTCRng15A;
    //LmitsSafe
    //LImtisHard
    valid := true;
  end;

  EventQueuePTCServer := TMyStringQueueThreadSafe.Create(2000);
end;


destructor TKolPTCObject.Destroy;
begin
  fConfClient.Destroy;
  fTCPClient.Destroy;
  MyDestroyAndNil( fLog );
  //if KolTCPClient<>nil then KolTCPClient.Destroy;
  EventQueuePTCServer.Destroy;
  inherited;
end;


//--------------------------------------------



function TKolPTCObject.GetPTCServerAppPath: string;
Var
  res, PID: longword;
  s: string;
begin
  s := '';
  fPTCServerPID := GetPTCServerPID;
  res := MyGetFileNameByProcessID( fPTCServerPID, s);
  if res>0 then logmsg( 'ERROR GetPTCServerAppPath PID=' + IntToStr( fPTCServerPID ) + 'rescode ='  + IntToStr( res ) );
  if res=0 then logmsg( 'GetPTCServerAppPath PID=' + IntToStr( fPTCServerPID ) + ' path ='  + s );
  Result := ExtractFilePath( s );
end;



function TKolPTCObject.GetPTCServerPID: longword;
begin
  Result := myGetProcessPID( 'PtcServer.exe' );
  logmsg( 'GetPTCServerPID PID=' + IntToStr( Result ) );
end;



function TKolPTCObject.StartPTCServer(): boolean;
//From http://stackoverflow.com/questions/12637203/why-does-createprocess-give-error-193-1-is-not-a-valid-win32-app
var
 WorkDir, Filename: string;
 Arguments : string;
  StartupInfo  : TStartupInfo;
  ProcessInfo  : TProcessInformation;
  lCmd         : string;
  lOK          : Boolean;
  LastErrorCode: Integer;
begin
//check if running:
  Result := false;
  fPTCServerPId := 0;
  if  GetPTCServerPID<>0 then
    begin
      Result := true;
      exit;
    end;
//
  FillChar( StartupInfo, SizeOf( TStartupInfo ), 0 );
  StartupInfo.cb := SizeOf( TStartupInfo );
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := SW_SHOWMINIMIZED; //sw_Normal;

  FillChar( ProcessInfo, SizeOf( TProcessInformation ), 0 );

  Workdir := GlobalConfig.globAppDir;
  FileName := fPTCSrvExeName;
  Arguments := '';
  lCmd := '"' +  WorkDir + '\' + FileName + '"';     // Quotes are needed http://stackoverflow.com/questions/265650/paths-and-createprocess
  if Arguments <> '' then lCmd := lCmd + ' ' + Arguments;


  logmsg(' StartPTCServer    Try Create Process');
  try
  lOk := CreateProcess(nil,
                       PChar(lCmd),
                       nil,
                       nil,
                       FALSE,  // TRUE makes no difference
                       0,      // e.g. CREATE_NEW_CONSOLE or NORMAL_PRIORITY_CLASS makes no difference
                       nil,
                       nil,    // PChar(WorkDir) makes no difference
                       StartupInfo,
                       ProcessInfo);
  except
    on E: exception do begin lOK:= false; ShowMessage('E: ' +  E.Message) end;
  end;
   if lOK then
     begin
       fPTCServerStartedHere := true;
       fPTCServerPId := ProcessInfo.dwProcessId;
       fPTCServerHProcess :=  ProcessInfo.hProcess;
       //
       Result := true;
       //
     end
   else
      begin
       fPTCServerStartedHere := false;
       fPTCServerPId := 0;
     end;
  Result := lOK;
end;






function TKolPTCObject.KillPTCServer(): boolean;
//From http://stackoverflow.com/questions/12637203/why-does-createprocess-give-error-193-1-is-not-a-valid-win32-app
var
  h: THandle;
  pid: cardinal;
  b: boolean;
begin
  logmsg( 'KillPTCServerPID');
  h:= 0;
  {
  if fPTCServerStartedHere then
    begin
      pid := GetPTCServerPID;
      //h := Open
      if pid<>0 then TerminateProcessByID(pid); //CloseHandle(h);
      fPTCServerStartedHere := false;
      exit;
    end;}
  pid := GetPTCServerPID;
  if pid<>0 then
    begin
      try
        //TerminateProcessByID(pid);  does not seem to wwork!!!
        //use HARD and DIRECT WAY
         h := OpenProcess(PROCESS_TERMINATE,  False, pid);
         //PROCESS_QUERY_LIMITED_INFORMATION
         //TerminateProcess( h , 0);
         //CloseHandle(ProcessHandle);
         if (h=0) and fPTCServerStartedHere then h := fPTCServerHProcess;
         if h=0 then LogWarning('PtcSRV handle  = 0 !!! ');
         if h<>0 then
           begin
             //postmessage(h, $0010, 0, 0);         //    WM_CLOSE
             b := TerminateProcess( h , 0);
             CloseHandle(h);
             LogMSG('PtcSRV termiante result: ' + BoolToStr( b ));
           end;
      except
        on E: exception do begin end;
      end;
    end;
  logmsg( '      PID=' + IntToStr(pid ) + '   handle=' + IntToStr( h ));
end;




procedure TKolPTCObject.SaveLastState;
begin
  fSavedPTCState.OutputOn := fLastKolPtcStatus.OutputOn;
  fSavedPTCState.Setpoint := fLastKolPtcStatus.Setpoint;
  fSavedPTCState.Feedback  := InternalFBToKol( fLastKolPtcStatus.FeedbackRaw );
  fSavedPTCState.IRange  := InternalRngToKol( fLastKolPtcStatus.RangeRaw );
  fSavedPTCState.Valid := true;
end;

procedure TKolPTCObject.RestoreLastState;
begin
  if not fSavedPTCState.Valid then exit;
  SetRange( fSavedPTCState.IRange );
  SetFeedback( fSavedPTCState.Feedback );
  SetSetpoint( fSavedPTCState.Setpoint );
  SetOutputRelay( fSavedPTCState.OutputOn );
end;                                                         






procedure TKolPTCObject.RestartPTCServer;
begin
  if not fPTCServerRestartEnabled then exit;
//  SaveLastState;
//  Finalize;
//  KillPTCServer;
     /// NO!! //kolPTC.StartPTCServer;  //will be started in initialzie
//  Initialize;
//  RestoreLastState;
  RequestRestartServer := false;
end;




function TKolPTCObject.MakeSureServerRunsOrStartIt: boolean;
begin
    Result := false;
  if GetPTCServerPID=0 then
    Result := StartPTCServer()
  else
    Result := true;
end;

function TKolPTCObject.IsPTCServerRunning: boolean;
begin
  Result := GetPTCServerPID<>0;
end;


procedure TKolPTCObject.WaitForTCPServerStart(toutMS: longint=1000);
Var
 t0: longword;
begin
  t0 := TimeDeltaTICKgetT0;
  while ((GetPTCServerPID=0) and (TimeDeltaTICKNowMS(t0)< toutMS)) do
      begin
        sleep(100);
      end;
end;

procedure TKolPTCObject.WaitForTCPClientConnect(toutMS: longint=10000);
Var
 t0: longword;
begin
  t0 := TimeDeltaTICKgetT0;
  if not fTCPClient.IsConfigured then fTCPClient.ConfigureTCP(fTCPhost, fTCPport);
  fTCPClient.Open;
  while ((not fTCPClient.IsReady) and (TimeDeltaTICKNowMS(t0)< toutMS)) do
      begin
        fTCPClient.Open;
        if fTCPClient.IsReady then break;
        sleep(100);
      end;
end;



procedure TKolPTCObject.WaitForPing(toutMS: longint=10000);
Var
 t0: longword;
begin
  t0 := TimeDeltaTICKgetT0;
  while ((not PingPTC()) and (TimeDeltaTICKNowMS(t0)< toutMS)) do
      begin
        sleep(200);
      end;
end;


function TKolPTCObject.Connect(): boolean;
//For KolPTC I need first to have DLL LOADED - since it is dynamic, this will do it - it is neccessary to even check if it is available
Const
  CThisProcName = 'TKolPTCObject.Connect: ';
  Var
    b: boolean;
begin
{$R-}
  Result := false;
  if fConnectingLock then exit;
  fConnectingLock := true;
  fTCPconfigured := false;
  fTCPClient.Close;    //in case ti was open - to reinitialize
  fTCPClient.ConfigureTCP( fTCPhost, fTCPport);
  fTCPClient.ProtocolVer := fProtocolVer;
  fTCPconfigured := true;
  logmsg(' ' + CThisProcName + ' Configure done.');
  //chekc SERVER RUNNIG and start it if not
  logmsg(' ' + CThisProcName + ' Trying start of server.');
  b := false;
  if (GetPTCServerPID=0) and (fTCPhost = 'localhost') then
    begin
      logmsg('      PTC server not running && localhost -> start it:' + BoolToStr( b ) );
      b := StartPTCServer;
      sleep(100);
      logmsg('      wating for server app:');
      if b then WaitForTCPServerStart(5000);
      logmsg('      result start server:' + BoolToStr( b ) );
     end
    else logmsg('    OK - PTC server already running || not localhost' );
  logmsg('    Client connect try' );
  WaitForTCPClientConnect(500);
  fTCPLastTRYConnectDateTime := Now;
  if fTCPClient.IsReady then  logmsg('    OK client connected' ) else logmsg('    connect FAILED' );
  //now wait for server to truly establish conenction with HW - check by ping
  //
  Result := fTCPClient.IsReady;
  fConnectingLock := false;
end;


function TKolPTCObject.IsAvailable: boolean;
begin
  Result := fTCPClient.IsConfigured and fRegConfigured;
end;


function TKolPTCObject.CheckAvailable(): boolean;
Var
  b: boolean;
  s: string;
  xst: TKolPTCStatus;
begin
  Result := false;
  if not IsAvailable then exit;
  Result := fTCPClient.VerifyConnectionToServer();
  logmsg('  CheckAvailable  result: ' + BoolToStr( Result) );
end;



function TKolPTCObject.Initialize: boolean;
{19.7.2015: Zah�jen� mu�e vypadat tak, �e nastav� range, feedback a setpoint a pak povol� v�stup a on najede s�m.
Feedback lze na chodu zmenit, setpoint se tam automaticky zmen� taky tak, aby se "nic nestalo".
}
Const
  CThisProcName = 'TKolPTCObject.Initialize: ';
  toutsecs = 1;
  waitdelay = false;
Var
  timeout: TDateTime;
  kolextstatus: TKolPTCExtendedStatus;
  b, b2, b3: boolean;
  crcs, s: string;
begin
{$R-}
  Result := false;
  setIsReady(false);
  kolptclock := false;
  fRegWriteEnabled := false;
  fLastOCV := NAN;
  //fTCPClient.CLose; //in case was open to force reconnect
  //TODO show form with countodwn
  logmsg(' ' + CThisProcName + ' Start');
  //if necessary try to connect dll

  fTryingConnectionFlag := true;
  DebugLogTurnOnTemporary;
  logmsg(CThisProcName +' Start init...' );

  if (not fTCPconfigured) or (not fTCPClient.IsReady) then Connect;
  if not fTCPClient.IsReady then
    begin
      kolerrormsg(CThisProcName +' Failed Open Connection' );
      exit;
    end;
  //
  //Get info about PTCServer
  fPTCServerIsOnLocalhost := fTCPhost='localhost';
  fPTCServerAppPath := GetPTCServerAppPath;
  fPTCServerPID := GetPTCServerPID;
  if (fPTCServerAppPath='') and (fPTCServerIsOnLocalhost) then  fPTCServerAppPath :=  fPTCServerDefaultAppPath;
  logmsg(CThisProcName +' PTCServerAppPAth ...' + fPTCServerAppPath + '  fPTCServerDefaultAppPath');
  //check ptc server response

  if not CheckAvailable() then
    begin
      kolerrormsg(CThisProcName + 'PTC server not responding (checkavailable), exiting');
      exit;
    end;

  //ok now we have working connection to server - now try to talk to PTC directly

  if not PingPTC() then
    begin
      WaitForPing(1000);
      if not PingPTC() then
      begin
        kolerrormsg(CThisProcName + 'PTC server not responding (Ping - echo PTC), exiting');
        exit;
      end;
    end;

  //GET PTC_INFO - neccessary for aquiring data and contains info
  b2 := GetInfo;
  if not b2 then
    begin
      kolerrormsg(CThisProcName + 'PtcInfo: failed, cannot continue, exiting!');
      exit;
    end;
  //force initial state

  //  PTC is not yet declared ready - use only direct internal commands
  b:= false;
  kolmsg( '>> crc read');
  // if not match do not allow ready and showmessage
  b := ReadRegCRC( crcs );
   kolmsg( '  crc done ' + boolToStr(b));
  if crcs<>fRegVersionID then
    begin
      s := 'KolPTC: Config IS valid for DIFFERENT Firmware version (CRC do not match)!!! check PTC setup. Will abort.';
      ShowMessage(s);
      kolerrormsg(CThisProcName + s);
      exit;
    end;
  //
  kolmsg(CThisProcName + ': CRC config check -> MATCH -> enable write to registers and continue init');
  //allow reg writing
  fRegWriteEnabled := true;
  //
  b := ReadPTCStatusExtended( kolextstatus );
  if not b then
    begin
      kolErrormsg(CThisProcName + 'ReadEXTStatus FAILED! will abort');
      exit;
    end;
  //update present settings
  logmsg(CThisProcName + 'TurnLoadOFF');
  SetOutputRelay( false );
  logmsg(CThisProcName + 'SetRange 15A');
  SetRange( CPTCRng15A );
  logmsg(CThisProcName + 'SetFeedback: I');
  SetFeedback( CPTCFbI );
  logmsg(CThisProcName + 'SetSetpoint 0.0');
  SetSetpoint( 0.0 );
  //logmsg(CThisProcName + 'SetV4range: -0.1, 1.5');
  //SetSafetyRangeV4(-0.1, 1.5);
  //done
  kolmsg('TKolPTCObject.Initialize: Connected to kolPTC!!! This is interface: ' + CKolPtcIfaceVerLong );
  kolmsg('  HW info: ' + GetHWIdstr );
  kolmsg('  KolPTC OK & ready');
  fNameLong := 'HW: ' + GetHWIdstr;
  setIsReady(true); //fReady.valBool := true;
  Result := true;
end;

procedure TKolPTCObject.Finalize;
begin
  kolmsg('Disconnecting PTC');
  fConnectingLock := false;
  fRegWriteEnabled := false;
  if IsReady then
      begin
        TurnLoadOFF;
      end;
  fTCPClient.CLose;
  setLastAcqTimeMS(-1);
  setIsReady(false);
  //fAvailable := false;
  //if fDllFuncAssigned then Ptc_Exit;  //DO NOT USE PTC EXIT
  //Ptc_Exit; //call Ptc_exit onyl when cloasing app - bacause it will kill
  //           //dll background formp, and only way to get it back is completely restart the application (reload dll)
  //
  //fDllFuncAssigned := false;
  //UnLoadDll;
end;



function TKolPTCObject.GetFlags(): TPotentioFlagSet;
begin
  Result := fFlagSet;
end;



function TKolPTCObject.GetFuseMsg: string; //report last (HARD) FUSE error code and msg
Var
  b: boolean;
  s: string;
begin
  Result := 'ErrX';
  b := ReadRegLCDmsg(s);
  Result := IntToStr( fLastKolPtcStatus.FuseStatusRaw ) + '(0x'+ IntToHex(fLastKolPtcStatus.FuseStatusRaw, 4) + ') msg=' + s + '(' + BoolToStr(b) + ')';
end;



function TKolPTCObject.ResetFuse: boolean;  //recover from fuse event
Const
  procident = 'ResetFuse ';
Var
  bf, b: boolean;
  okcnt: integer;
  prstat: word;
  lmsg: string;
begin
  Result := false;
  kolMsg(procident + ' start reset fuse' );
  sleep(200);
  ReadRegProtectStatus( prstat);
  ReadRegLCDmsg(lmsg);
  kolmsg('  protect status=0x' + IntToHex(prstat, 8) + '  lcdmsg=' +  lmsg );
  bf := SetResetFuseCmd;
  okcnt := 0;
  if not fPTCDesiredState.valid then  kolMsg(procident + ' saved state NOT VALID, will not restore' );
  if fPTCDesiredState.valid then
    begin
      okcnt := 0;
      b := SetRange( fPTCDesiredState.IRange );
      if b then Inc(okcnt);
      b := SetFeedback( fPTCDesiredState.Feedback );
      if b then Inc(okcnt);                                       
      b := SetSetpoint( fPTCDesiredState.Setpoint );
      if b then Inc(okcnt);
      b := SetOutputRelay( fPTCDesiredState.OutputOn );
      if b then Inc(okcnt);
    end;
  Result := bf and (okcnt = 4);
  kolMsg('   finish reset fuse: ' + BoolToStr( Result ) );
end;

//--------------------------------





//basic control functions
function TKolPTCObject.AquireDataStatus(Var rec: TPotentioRec; Var Status: TPotentioStatus): boolean;
//description of inputs "ain":  now stoed in configuration record
Const
  CThisProcName = 'AquireDataStatus';
Var
    chdata: TKolPTCChannelData;
    kolstat: TKolPTCStatus;
    V2raw, V4raw, Vrefraw, Iraw, SPraw: double;
    Ifin, Ufin: double;
    b1, b2, b3 : boolean;
    bfuse: boolean;
    i: integer;
    n: byte;
    t0: Longword;
    feedback: TKolPTCFeedback;
begin
    //although this not very good place, it is called often!!!
    //check for temporary enable of debug and if need to be disabled
    if fTemporarydebugOn and (fTemporaryDebugOffTime< TimeDeltaTICKgetT0)  then
      begin
        fPTCdebug := false;
        fTemporarydebugOn := false;
      end;
    //
    //
    Result := false;
    InitPtcRecWithNAN( rec, status );
    rec.timestamp := Now();
    setLastAcqTimeMS(-1);
    //no check for available necessary - it is done on the lower level
    b1 := false;
    b2 := false;
    Exclude( fFlagSet, CPtcNotConfigured);
    //
    if (not fTCPConfigured) then
      begin
        fFlagSet := fFlagSet + [CPtcNotConfigured];        //set operations
        kolMsg('EEEE KolPTC not fTCPConfigured ');
        exit;
      end;
    if not IsAvailable then
      begin
        //kolMsg('EEEE KolPTC not available');
        FlagUpdate(true, CNotAvailable, fFlagSet);
        exit;
      end;
    //
    if fRequestRestartServer and (not fPTCServerRestartEnabled) then   //actually try reconnect TCP at least!!!!
    begin
      logwarning(' restartrequested - doing TCP reconnect to server');
      TCPTryReconnect;
      fRequestRestartServer := false;
    end;
    t0 := TimeDeltaTICKgetT0;
    try
      //importatnt check if PTCserver is really working OK -> if not NEED TO RESTART - and workaround the bug with reinitializing comport!!!!!!!!!!

    {  if not PingPTC then //every about 10s there is direct query to PTC - if it response, everything is OK.
        begin
          if not WaitForPTCPing(10000) then
            begin  //waiting failed - return false
             FlagUpdate(true, CPtcNotResponding, fFlagSet);
             logwarning(' EE during PING - PTC was not responding within time limit and wait failed -> exiting');
             exit;
            end;

        end;
      if fPTCServerRestartEnabled then if not PingPTC then fRequestRestartServer :=true;   //ping sends actually ping only every 20 seconds or so
    }
      // --end of PTC SERVER bug workaround
      //aquire channels //aquire basic status
      b1 := ReadPTCServer( chdata, kolstat ); //b1 := ReadChannels( chdata );
      b2 := true;    //b2 := ReadStatus( kolstat );
    except
      on E: Exception do
        begin
          kolErrorMsg('EEEE KolPTC AquireDatastatus EXCEPTION: ' + E.message);
          //reset LOCK !!!!!!!!!!!!!
          kolptclock := false;
          exit;
        end;
    end;
    setLastAcqTimeMS( TimeDeltaTICKNowMS(t0) );
    if not (b1 and b2) then
      begin
        //aquire failed
        kolmsg( CThisProcName + 'FAILED - exiting' );
        exit;
      end;
    //CHANNELS
    //use channel configuration to get values from raw data
    //
    //Current - TODO can decide if use I or Ix10 depending on range
    Iraw := chdata.I;
    //
    //Voltage
    V4raw := chdata.V4;
    Vrefraw := chdata.Vref;
    //
    //process U, I if necessary
    Ufin := V4raw;
    Ifin := Iraw;
    with rec do
    begin
        timestamp := Now;
        U := Ufin;
        I := Ifin;
        P := Ufin * Ifin;
        Uref := Vrefraw;
    end;
    //Setpoint @ Aout
    SPraw := kolstat.Setpoint;
    feedback := InternalFBToKol( kolstat.FeedbackRaw );
    //
    // keep track of last OCV
    if not kolstat.OutputOn then FlastOCV := Ufin;
    //store as last known data
    fLastPTCdata := rec;
    //
    //STATUS
    fLastKolPtcStatus := kolstat;
    FlagUpdate(kolstat.HWFuseActive, CPtcHardFuseActivated, fFlagSet);
    FlagUpdate(kolstat.SoftLimActive, CPtcSoftLimitationActive, fFlagSet);
    //TODO: check flag indicators (overrange)
    //U, I overrange
    if (not isNan(Ufin)) and (not isNan(Ifin)) then begin

       FlagUpdate( (Ufin < fRngVoltRec.low) or (Ufin > fRngVoltRec.high) , CPtcOverRangeVoltage, fFlagSet );
       FlagUpdate( (Ifin < fRngCurrRec.low) or (Ifin > fRngCurrRec.high) , CPtcOverRangeCurrent, fFlagSet );
    end;
     //
    with Status do
      begin
       flagSet := fFlagSet;
       setpoint := kolstat.Setpoint;
       mode := FBtoMode( feedback  );
       isLoadConnected := kolstat.OutputOn;
       rangeCurrent := KolRngToRngRec( InternalRngToKol( kolstat.RangeRaw ) );
       rangeVoltage := kolstat.V4HardRng;
       rngV4Safe :=  kolstat.V4SoftRng;
       rngV4hard :=  kolstat.V4HardRng;
       //                                                          //set
       debuglogmsg := 'Output=' + BoolToStr(kolstat.OutputOn) +
                      '|HWFuse=' + BoolToStr(CPtcHardFuseActivated in flagSet) +
                      '|SWLim=' + BoolToStr(CPtcSoftLimitationActive in flagSet) +
                      '|ModeRaw=' + IntToStr( kolstat.FeedbackRaw ) +
                      '|setp=' + FloatToStrF(setpoint, ffFixed, 4,2) +
                      '|Range=' + IntToStr(kolstat.RangeRaw) +
                      '|Health_VPout_VNOUT_IPout_INout_IP12_IN12='
                           + FloatToStr(kolstat.VPout) + '_'
                           + FloatToStr(kolstat.VNout) + '_'
                           + FloatToStr(kolstat.IPout) + '_'
                           + FloatToStr(kolstat.INout) + '_'
                           + FloatToStr(kolstat.IP12) + '_'
                           + FloatToStr(kolstat.IN12) + '_'  +
                      '|FuseStatus=' + IntToStr(kolstat.FuseStatusRaw);
      end;
  //store as last known data
  fLastPTCStatus := Status;
  //
  //CHECK DESIRED STATE AND IF NOT OK RESEND NEW SETTINGS
  if true and (fPTCDesiredState.valid) then
    begin
      if fPTCDesiredState.OutputOn <> kolstat.OutputOn then
        begin
          LogWarning( 'KolPTC checkDesiredState: OutputON different, should be: ' + BoolToStr(fPTCDesiredState.OutputOn)  );
          SetOutputRelay( fPTCDesiredState.OutputOn );
        end;

      if fPTCDesiredState.Feedback <> feedback then
        begin
          LogWarning( 'KolPTC checkDesiredState: FEEDBACK different, was ' + IntToStr( Ord(feedback) ) + ' should be: ' +  KolFBToStr( fPTCDesiredState.Feedback ) + ' (' + IntToStr( ord(fPTCDesiredState.Feedback) ) );
          SetFeedback( fPTCDesiredState.Feedback );
        end;

      if not CompareEpsilonAequalB(  fPTCDesiredState.Setpoint, kolstat.Setpoint, 1E-6) then
        begin
          LogWarning( 'KolPTC checkDesiredState: SETPOINT different, should be: ' + FloatToStr(fPTCDesiredState.Setpoint) + ' and was: ' + FloatToStr(kolstat.Setpoint)   );
          SetSetpoint( fPTCDesiredState.Setpoint );
        end;

    end;
  //
  //finished
  Result := true;
end;


{
function TKolPTCObject.AquireStatus(Var Status: TPotentioStatus): boolean; //quickly retrieves only status
Const
  CThisProcName = 'AquireStatus';
Var
    kolstat: TKolPTCStatus;
    b2: boolean;
    i: integer;
    n: byte;
    rec: TPotentioRec; //dummy
begin
    Result := false;
    InitPtcRecWithNAN( rec, status );
    //no check for available necessary - it is done on the lower level
    //aquire basic status
    b2 := ReadStatus( kolstat );
    if not (b2) then
      begin
        //aquire failed
        kolmsg( CThisProcName + 'FAILED - exiting' );
        exit;
      end;
    //STATUS
    fLastKolPtcStatus := kolstat;
    Exclude(fFlagSet, CPtcFuseActivated);
    if kolstat.FuseActive then Include(fFlagSet, CPtcFuseActivated);
    //
    with Status do
      begin
       flagSet := fFlagSet;
       setpoint := kolstat.Setpoint;
       mode := FBtoMode( InternalFBToKol( kolstat.Feedback ) );
       isLoadConnected := kolstat.OutputOn;
       rangeCurrent := KolRngToRngRec( InternalRngToKol( kolstat.Range ) );
       rangeVoltage := CPTCZeroRng;
       //                                                          //set
       debuglogmsg := 'N/A';
      end;
  //store as last known data
  fLastPTCStatus := Status;
  //finished
  Result := true;
end; }


function TKolPTCObject.SetCC( val: double): boolean;
begin
  Result :=  SetCCx( val);
end;


function TKolPTCObject.SetCV( val: double): boolean;
begin
  if CDebug then kolmsg('SetCV: in here');
  Result :=  SetCVx( val);
end;


procedure TKolPTCObject.WaitForSetpointCurr;
Const
  Ctimeout = 20000;
  Cepsilon = 0.05;  //5%
Var
  tstrt: TDateTime;
  done: boolean;
  rec: TPotentioRec;
  status: TPotentioStatus;
  b: boolean;
  dif, dd: double;
begin
  tstrt := now;
  done := false;
  while (MilliSecondsBetween(Now, tstrt) < ctimeout) and not done do
    begin
      b := AquireDataStatus(Rec, Status);
      dif := fLastPTCStatus.setpoint - Rec.I;
      if dif < fLastPTCStatus.setpoint * Cepsilon then
        begin
          done := true;
          break;
        end;
    end;
end;







function TKolPTCObject.TurnLOADON: boolean;
Var
  b: boolean;
begin
  Result := false;
  if CDebug then kolmsg('TKolPTCObject.TurnLOAD ON' );
  b := SetOutputRelay( true );
  if not b then kolerrormsg('Turn on: failed');
  Result := b;
end;


function TKolPTCObject.TurnLOADOFF: boolean;
Var
  b: boolean;
begin
  Result := false;
  if CDebug then logmsg('TKolPTCObject.TurnLOAD OFF' );
  b := SetOutputRelay( false );
  if not b then  kolerrormsg('Turn oFF: failed');
  Result := b;
end;



function TKolPTCObject.DecreaseCurrent: boolean;
Var
  b: boolean;
begin
  Result := false;
  if not IsAvailable then
  begin
   kolerrormsg('Decrease current: PTC not available');
   exit;
  end;
  if CDebug then logmsg('TKolPTCObject.DecreaseCurrent');
  //
  if ( (fLastPTCStatus.mode=CpoTCC)  ) then
     begin
       b :=   SetSetpoint(0.0);
       if not b then kolerrormsg('TKolPTCObject.DecreaseCurrent SetCC: setsetpoiont failed');
     end
  else if ( (fLastPTCStatus.mode=CpoTCV) ) and ( not isnan(FlastOCV) ) then
     begin
      //TODO: !!!!!!!!!  jsut to be safe this is hard limit for FlastOCV - it should not be here in normal case
       //if FlastOCV > 1.3 then FlastOCV := 1.3;
       //if FlastOCV < 0.8 then FlastOCV := 0.8;
       //TODO: end
       b := SetSetpoint(FlastOCV);
       if not b then kolerrormsg('TKolPTCObject.DecreaseCurrent SetCV: setsetpoiont failed');
     end
  else
    begin
      kolerrormsg('TKolPTCObject.DecreaseCurrent: error in last mode or no FlastOCV valid - doing nothing');
    end;
  //TODO: delay more - best until setpoint is reached
  DelayMS(1000);
  Result := true;
end;





function DivideReplyIntoParts( readreply: string; Var namestr, valstr: string): boolean;
Var
  toklist: TTokenList;
  b: boolean;
begin
  Result := false;
  namestr := '';
  valstr := '';
  b := ParseStrSep( readreply, ' ', toklist );
  if (not b) or (length(toklist)<3) then exit;
  if toklist[0].s <> 'read' then exit;
  namestr := toklist[1].s;
  valstr := toklist[2].s;
  Result := true;
end;

function ProcesReplyIntoKeyValList( replydata: string; Var sl: TStringList): boolean;
Var
  toklist: TTokenList;
  b1, b, bx : boolean;
  i: integer;
  ns, vs:  string;
begin
  Result := false;
  if sl=nil then exit;
  b1 := ParseStrSep( replydata, ';', toklist );
  if not b1 then exit;
  sl.Clear;
  if length( toklist)<1 then
    begin
      Result := true;
      exit;
    end;
  b := true;
  try
    for i:=0 to length( toklist)-1 do
      begin
        bx := DivideReplyIntoParts( toklist[i].s, ns, vs);
        b := b and bx;
        sl.Add(ns + '='+ vs);
      end;
  except
    Result := false;
    sl.Clear;
    exit;
  end;
  Result := b;
end;


function GetValFromSl( Var sl: TStringList; name: string; Var val: string): boolean;
begin
  Result := false;
  try
    val := sl.Values[name];
    Result := true;
  except
    on E: Exception do LogMsg(' EXCEPTION in GetValFromSl: ' + E.Message);
  end;
end;



function MyXStrToInt( val: string): longint;
begin
  try
    //Result := StrToIntDef(val, High(longint));
    Result := StrToIntDef(val, 0);
  except
    on E: Exception do
      begin
        LogMsg(' EXCEPTION in MyStrToInt: ' + E.Message);
        Result := High(longint);
      end;
  end;
end;

procedure TKolPTCObject.TryResync;
Const
  procident = 'TryResync: ';
Var
  b, b1, b2, b3, ok, resyncneeded: boolean;
  echostr, cmd, rep: string;
  i, j, len, k: longint;
  dts: longword;
begin
  if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  kolmsg(procident + 'start');
  //send echo and wait low level until reply comes back
  echostr := '#tryingresync echo';
  cmd := echostr + #13#10;
  kolmsg(procident + ' sending ECHO');
  b := fTCPClient.SendStringRaw(cmd);
  for j:=1 to 100 do
    begin
      b1 := fTCPClient.ReadStringRaw(rep, len, 1000);
      kolmsg(procident + 'wait for echo reply, cycle '+ IntToStr(j) + ': ' + BinStrToPrintStr(rep));
      if b1 then
        begin
           i := posex( echostr, rep, 1);  //space after idstr
           if i>0 then break; //OK
        end;
    end;
  if i>0 then
    begin
      kolmsg(procident + ' OK echo received back OK on iter:'+ IntToStr(j) );
      //b := TCPSendCmdRetry(cmd, rep);  //one more echo;
    end
  else
    begin
      kolmsg(procident + ' wait for ECHO failed!!! SOMETHING IS WRONG');
      //signal to restart ptc sertver!!!!!
      logwarning('NEED to restart PTCServer');
      fRequestRestartServer := true;
      //
    end;
  kolmsg(procident + 'end');
  Unlock;
end;




procedure TKolPTCObject.HandlePTCEvent(eventstr: string);
Var
   i: integer;
   s: string;
begin
  kolmsg('got EVENT ' + eventstr );
  //remove trailing EVENT
  i := length('EVENT ');
  s := midstr(eventstr, i+1, length(eventstr)-i+2 );
  EventQueuePTCServer.PushMsg( s, true );
end;







// internal aquiring functions


function TKolPTCObject.ReadPTCServer(Var chdata: TKolPTCChannelData; Var st: TKolPTCStatus): boolean;
Const
  procident = 'ReadPTCServer';
Var
  b, okdata, okstatus: boolean;
  rng: TRangeRecord;
  okcnt: integer;
  i: longint;
  d: double;
  varlist, reslist: TStringList;
  valstr: string;
  protst: word;
begin
  Result := false;
  if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  //
  varlist := TStringList.Create;
  varlist.Capacity := 50;
  reslist := TStringList.Create;
  reslist.Capacity := 50;
  varlist.Clear;

  if fPTCVersion<=0 then
    begin
        varlist.Add('V2');
        varlist.Add('V4');
        varlist.Add('Vref');
        varlist.Add('I');
        varlist.Add('Ix10');
        varlist.Add('PTC.IuA');
        varlist.Add('Setpoint');
        varlist.Add('Range');
        varlist.Add('Feedback');
        varlist.Add('OutputEnabled');
        varlist.Add('FuseStatus');
        varlist.Add('PTC.VPOut');
        varlist.Add('PTC.VNOut');
        varlist.Add('PTC.IPOut');
        varlist.Add('PTC.INOut');
        varlist.Add('PTC.IP12');
        varlist.Add('PTC.IN12');
    end
  else if fPTCVersion>=1 then
    begin
        varlist.Add('VOut');
        varlist.Add('VSense');
        varlist.Add('Vref');
        varlist.Add('I');
        varlist.Add('Setpoint');
        varlist.Add('IRange');
        varlist.Add('Feedback');
        varlist.Add('OutputEnabled');
        varlist.Add('FuseStatus');
    end;

  //
  //query
  b := fTCPClient.QueryGetVariables(varlist, reslist, fTCPTimeout);
  //
  //process
    if fPTCVersion<=0 then
    begin
           okcnt := 0;
           if GetValFromSl(reslist, 'V2', valstr) then  //V2    PTC.Vout
             begin
               Inc(okcnt);
               chdata.V2 := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'V4', valstr) then
             begin
               Inc(okcnt);
               chdata.V4 := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'Vref', valstr) then
             begin
               Inc(okcnt);
               chdata.Vref := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'I', valstr) then
             begin
               Inc(okcnt);
               chdata.I := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'Ix10', valstr) then
             begin
               Inc(okcnt);
               chdata.Ix10 := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'PTC.IuA', valstr) then
             begin
               Inc(okcnt);
               chdata.AC:= MyStrToFloat( valstr );
             end;
           okdata := (okcnt>=6);
           //
           //status
           //
           okcnt := 0;
           if GetValFromSl(reslist, 'Setpoint', valstr) then
             begin
               Inc(okcnt);
               st.Setpoint := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'Range', valstr) then
             begin
               Inc(okcnt);
               st.RangeRaw := MyXStrToInt( valstr );
             end;
           if GetValFromSl(reslist, 'Feedback', valstr) then
             begin
               Inc(okcnt);
               st.FeedbackRaw := MyXStrToInt( valstr );
             end;
           if GetValFromSl(reslist, 'OutputEnabled', valstr) then
             begin
               Inc(okcnt);
               st.OutputOn := MyXStrToInt( valstr )<>0;
             end;
           if GetValFromSl(reslist, 'FuseStatus', valstr) then
             begin
               Inc(okcnt);
               protst := MyXStrToInt( valstr );
               st.FuseStatusRaw := protst;
               if fFuseProtectUseOldStyle then
                 begin
                    st.HWFuseActive := ((protst and $01) = 0) or ((protst and $08)<>0);
                    st.SoftLimActive := (protst and $04) <> 0;
                 end
               else
                 begin
                    st.SoftLimActive := (protst and $0004) <> 0;
                    st.HWFuseActive := (protst and $00FB) <> 0;   //st.HWFuseActive := ((protst and $0001) = 1) or ((protst and $0008)<>0);
                 end;
             end;
           okstatus := (okcnt>=5);
        //other status data
         if GetValFromSl(reslist, 'PTC.VPOut', valstr) then st.VPout := MyStrToFloat( valstr );
         if GetValFromSl(reslist, 'PTC.VNOut', valstr) then st.VNout := MyStrToFloat( valstr );
         if GetValFromSl(reslist, 'PTC.IPOut', valstr) then st.IPout := MyStrToFloat( valstr );
         if GetValFromSl(reslist, 'PTC.INOut', valstr) then st.INout := MyStrToFloat( valstr );
         if GetValFromSl(reslist, 'PTC.IP12', valstr) then st.IP12 := MyStrToFloat( valstr );
         if GetValFromSl(reslist, 'PTC.IN12', valstr) then st.IN12 := MyStrToFloat( valstr );

    end
  else if fPTCVersion>=1 then
    begin
           okcnt := 0;
           if GetValFromSl(reslist, 'VOut', valstr) then  //V2    PTC.Vout
             begin
               Inc(okcnt);
               chdata.V2 := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'VSense', valstr) then
             begin
               Inc(okcnt);
               chdata.V4 := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'Vref', valstr) then
             begin
               Inc(okcnt);
               chdata.Vref := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'I', valstr) then
             begin
               Inc(okcnt);
               chdata.I := MyStrToFloat( valstr );
             end;
           chdata.Ix10 := 0;
           chdata.AC:= 0;
           okdata := (okcnt>=4);
           //
           //status
           //
           okcnt := 0;
           if GetValFromSl(reslist, 'Setpoint', valstr) then
             begin
               Inc(okcnt);
               st.Setpoint := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'IRange', valstr) then
             begin
               Inc(okcnt);
               st.RangeRaw := MyXStrToInt( valstr );
             end;
           if GetValFromSl(reslist, 'Feedback', valstr) then
             begin
               Inc(okcnt);
               st.FeedbackRaw := MyXStrToInt( valstr );
             end;
           if GetValFromSl(reslist, 'OutputEnabled', valstr) then
             begin
               Inc(okcnt);
               st.OutputOn := MyXStrToInt( valstr )<>0;
             end;
           if GetValFromSl(reslist, 'FuseStatus', valstr) then
             begin
               Inc(okcnt);
               protst := MyXStrToInt( valstr );
               st.FuseStatusRaw := protst;
               if fFuseProtectUseOldStyle then
                 begin
                    st.HWFuseActive := ((protst and $01) = 0) or ((protst and $08)<>0);
                    st.SoftLimActive := (protst and $04) <> 0;
                 end
               else
                 begin
                    st.SoftLimActive := (protst and $0004) <> 0;
                    st.HWFuseActive := (protst and $00FB) <> 0;   //st.HWFuseActive := ((protst and $0001) = 1) or ((protst and $0008)<>0);
                 end;
             end;
           okstatus := (okcnt>=5);
        //other status data
        st.VPout := NAN;
        st.VNout := NAN;
        st.IPout := NAN;
        st.INout := NAN;
        st.IP12 := NAN;
        st.IN12 := NAN;
    end;

//  if fPTCVersion<=0 then
//    begin
//
//    end
//  else if fPTCVersion>=1 then
//    begin
//
//    end;


  //V4MONitor sinking current workaround - use Vref channel instead !!!!!
  if fUseVrefInsteadOfV4 then
    begin
     //switch V4 and Vref data
      d := chdata.V4;
      chdata.V4 := chdata.Vref;
      chdata.Vref := d;
    end;

  //correct for PTC1 special channel setup bug  PTC server should read I at different channel
  //TEMPORARY  !!!!!!!!!!!!!!!!
  if fPTC1_IchannelWorkaround then
    begin
      chdata.I := chdata.AC;
    end;

   st.V4HardRng := fRngV4HardLimit;  //for now - copy only last know value, do not query PTC!! - only ocassionally
   st.V4SoftRng := fRngV4SWLimit;   //TODO check it !!!!

  if okstatus then fLastKolPtcStatus := st;

  Unlock;

  Result := b and okdata and okstatus;

  varlist.Destroy;
  reslist.Destroy;
end;






function TKolPTCObject.ReadPTCStatusExtended(Var extst: TKolPTCExtendedStatus): boolean;  //read maximum info status from PTC registers
Const
  CThisProcName = 'ReadStatusExt';
Var
  b: boolean;
  ad: TArrayOfDouble;
begin
  Result := false;
  b := true;
  b := b and ReadRegADC( ad );
  CopyDynArrayToStatic(ad, extst.RegADC, extst.RegADC_n);

  if fPTCVersion<=0 then
    begin
        b := b and  ReadRegRelayOn( extst.RegRelayOn );
        b := b and  ReadRegSetpoint( extst.RegSetpoint);
        b := b and  ReadRegSwFeedback( extst.RegSwFeedback );
        b := b and ReadRegProtectStatus( extst.RegProtectStat );
        //
        b := b and   ReadRegFwFuseSoft( ad );
        CopyDynArrayToStatic(ad, extst.RegFuse_safe, extst.RegFuse_safe_n);
        //
        b := b and   ReadRegFwFuseHard( ad );
        CopyDynArrayToStatic(ad, extst.RegFuse_hard, extst.RegFuse_hard_n);
        //
        b := b and ReadRegMonI( ad );
        CopyDynArrayToStatic(ad, extst.RegMonI, extst.RegMonI_n);
        //
        b := b and  ReadRegCRC( extst.CRCstr );
        b := b and ReadV4range( extst.V4range );
    end
  else if fPTCVersion>=1 then
    begin

    end;

  Result := b;
end;


//----------------


function ExtractReply(Var buf:string): string;  //returns part of the string up to the pakcet end identifier (<CR> in this case)
Const
  CMarkEnd = #13#10;
Var
  i: longword;
  tmp: string;
begin
  Result := '';
  i := Pos(CMarkEnd, buf);
  if i>0 then
    begin
      Result := Copy(buf, 0 , i-1);
    end
  else Result := buf + '';
end;


procedure TKolPTCObject.TCPDisconnect;
begin
  fTCPClient.Close;
end;


procedure TKolPTCObject.TCPTryReconnect;
begin
  if TimeDeltaNowMS(fTCPLastTRYConnectDateTime) > 10000 then
    begin
      logwarning(' REQUEST for TCP CLIENT reconnect - connection was lost before? ');
      TCPDisconnect;
      Connect;
      //fTCPLastTRYConnectDateTime := Now;
    end;
end;

function TKolPTCObject.TCPSendUserCMD(cmd: string; Var reply: string; timeout: longint): boolean;
//this does not care about kol-lock - expecting to be called from inside locked sequence
Var
  bs, br, ok:boolean;
  tr, dts, dtr, tw: longword;
  len: integer;
  srep, sss: string;
begin
  Result := false;
  reply := '';
  if fTCPClient = nil then exit;
  if timeout<1 then timeout := high(longint);
  cmd := cmd + #13#10;
  Result := fTCPClient.QueryCmdReliable(cmd, reply, timeout);
end;



function TKolPTCObject.TCPSendReceive(cmd: string; Var reply: string; timeout: longint): boolean;
//this does not care about kol-lock - expecting to be called from inside locked sequence
Var
  bs, br, ok:boolean;
  tr, dts, dtr, tw: longword;
  len: integer;
  srep, sss: string;
begin
  Result := false;
  reply := '';
  if fTCPClient = nil then exit;
  if not fTCPClient.IsReady then
    begin
      TCPTryReconnect;
      if not fTCPClient.IsReady then exit;
    end;
  if timeout<1 then timeout := high(longint);
  cmd := cmd + #13#10;
  bs := fTCPClient.SendStringRaw(cmd);
  tr := TimeDeltaTICKgetT0;
  if bs then
    begin
         br := false;
         sss := '';
         tw := TimeDeltaTICKgetT0;
         while true do
            begin
              ok := fTCPClient.ReadStringRaw(srep, len, timeout);
              if ok then sss := sss + srep;
              if TCPIsEndOfMessage( sss ) then
                begin
                  br := true;
                  break;
                end;
              if TimeDeltaTICKNowMS(tw)>timeout then break;
            end;
    end;
  dtr := TimeDeltaTICKNowMS( tr );
  if br then
    begin
      reply := ExtractReply( srep );
    end;

  Result := bs and br;
end;


function TKolPTCObject.TCPIsEndOfMessage( reply: string ): boolean;
Var
  i: longint;
begin
  Result := false;
  i := posex( #13#10 , reply);  //space after idstr
  if i>0 then Result := true;
end;


procedure TKolPTCObject.DebugLogTurnOnTemporary;
begin
  fPtcDebug := true;
  fTemporarydebugOn := true;
  fTemporaryDebugOffTime := TimeDeltaTICKgetT0 + 60000;
end;


function TKolPTCObject.TCPSendCmdRetry(cmd: string; Var reply: string): boolean;
//this does not care about kol-lock - expecting to be called from inside locked sequence
Var
  b, cmdres: boolean;
  retry, cnt: integer;
  timeout: longint;
begin
  Result := false;
  reply := '';
  retry := fRetryCount;
  timeout := fTCPTimeout;
  if retry<1 then retry := 1;
  cnt := 0;
  if fPTCdebug then LeaveLogMsg('TCPSendCmdRetry: sending |' + BinStrToPrintStr( cmd )+ '|' );
  //b := TCPSendReceive(cmd, reply, timeout);
  b := fTCPClient.QueryCmdReliable(cmd, reply, timeout);
  //retry := 0;   //why?
  while (not b) and (retry>0) do
    begin
      if fPTCDebug and (cnt>0) then LeaveLogMsg('TCPSendCmdRetry: retry cmd #' + IntToStr( cnt +1 ) );
      b := fTCPClient.QueryCmdReliable(cmd, reply, timeout); //b := TCPSendReceive(' ', reply, timeout);
      if b then break;
      LeaveLogMsg('TCPSendCmdRetry:    SendReceive failed (TIMEOUT), will try more? retry=' + IntToStr( retry ) + '  cmd: '  + BinStrToPrintStr(cmd) + ' reply ' + BinStrToPrintStr(reply));
      LeaveLogMsg('TCPSendCmdRetry:    Turning on debug logging for 1 minute');
      DebugLogTurnOnTemporary;
      inc( cnt );
      dec( retry );
    end;

  {
  while retry>0 do
    begin
      if fPTCDebug and (cnt>0) then LeaveLogMsg('TCPSendCmdRetry: retry cmd #' + IntToStr( cnt +1 ) );
      b := TCPSendReceive(cmd, reply, timeout);
      if b then break;
      LeaveLogMsg('TCPSendCmdRetry:    SendReceive failed (TIMEOUT), will try more? retry=' + IntToStr( retry ) + '  cmd: '  + BinStrToPrintStr(cmd) + ' reply ' + BinStrToPrintStr(reply));
      LeaveLogMsg('TCPSendCmdRetry:    Turning on debug logging for 1 minute');
      DebugLogTurnOnTemporary;
      inc( cnt );
      dec( retry );
    end;
    }
  if fPTCdebug then LeaveLogMsg('     received(' +  BoolToStr(b) + '): |' + BinStrToPrintStr( reply )+ '|' );
  Result := b;
end;


function TKolPTCObject.EncodeLowLevelCmdforTCP(Var buf: TKolBuffer): string;
//for TCP PtcQuery command bin sequence coded as string of hex codes
Var
  cmd: string;
  i: longint;
begin
  cmd := 'QueryPtc ';
  for i:= 0 to length(buf)-1 do
    begin
      cmd := cmd + ByteToHexStr(buf[i]);
      if i< length(buf)-1 then cmd := cmd + ' ';
    end;
  cmd := cmd; //no need to add crlf + #13#10;
  Result := cmd;
end;

function TKolPTCObject.DecodeLowLevelCmdReply(Var rep: string; Var buf:TKolBuffer): boolean;
//for TCP PtcQuery command bin sequence coded as string of hex codes
Var
  cmd, r: string;
  i, len, nbytes: longint;
  ok, bp : boolean;
  tl: TTokenList;
begin
  Result := false;
  len := length(rep);
  nbytes := 0;
  SetLength( buf, 0);
  //expect 'OK' at begin  and CRLF at end;
  if len<2 then exit;
  bp := ParseStrSimple(rep, tl);
  if Length(tl)<1 then exit;
  ok := tl[0].s = 'OK';
  if not ok then exit;
  Result := ok;
  if length(tl)<2 then exit;
  setlength( buf, length(tl)-1 );
  //
  Result := true;
  if length(tl)<=1 then exit;
  for i:= 1 to length(tl)-1 do buf[i-1] := HexStrToByte( tl[i].s );   //strtohex
end;




function TKolPTCObject.TCPSendPtcQueryLowLevel(Var bufin: TKolBuffer; Var bufout: TKolBuffer): boolean;  //using TCP PtcQuery command
Const
  ThisProcName =  'TCPSendPtcQueryLowLevel';
Var
  sendstr, repstr: string;
  bsend: boolean;
begin
  Result := false;
  SetLength( bufout, 0 );
  sendstr := EncodeLowLevelCmdforTCP(bufin );
  if fPTCDebug then LeaveLogMsg(ThisProcName + ': sending |' + sendstr + '|');
  bsend := TCPSendCmdRetry(sendstr, repstr);
  if bsend then
    begin
      Result := DecodeLowLevelCmdReply(repstr, bufout);
      if fPTCDebug then LeaveLogMsg('              received |' + repstr + '|');
    end;
  if not bsend then LeaveLogMsg(ThisProcName + ': send failed!');
  if bsend and (not Result) then LeaveLogMsg(ThisProcName + ': receive failed!');
end;


function TKolPTCObject.TCPSendPtcQuery(Var bufin: TKolBuffer; Var bufout: TKolBuffer; Timeout: longint; Var PtcFlags: TPotentioFlagSet): boolean;  //using TCP PtcQuery command
Const
  ThisProcName =  'TCPSendPtcQueryHL';
Var
  sendstr, repstr: string;
  b, bsend: boolean;
  t0: longint;
begin
  Result := false;
  FlagUpdate( false, CServerNotResponding, ptcflags);
  FlagUpdate( false, CPtcNotResponding, ptcflags);

  SetLength( bufout, 0 );
  sendstr := EncodeLowLevelCmdforTCP(bufin );

  if fPTCDebug then LeaveLogMsg(ThisProcName + ': sending |' + sendstr + '|');
  t0 := TimeDeltaTICKgetT0;

  while (TimeDeltaTICKNowMS(t0) < timeout) do
    begin
      //b := TCPSendPtcQueryLowLevel(bufin, bufout);
      bsend := TCPSendCmdRetry(sendstr, repstr); //bsend := TCPSendCmdRetry(sendstr, repstr);
      if not bsend then
        begin
          if DebugEnabled then LogWarning(ThisProcName + ': TCPSendPtcQueryLowLevel failed -> exiting');
          FlagUpdate( true, CServerNotResponding, ptcflags);
          exit;
        end;
      //ok query was send, now check if ptc responded OK
      b := DecodeLowLevelCmdReply(repstr, bufout);
      if b then
        begin
          //OK!!!  be happy
          Result := true;
          break;
        end
      else
        begin
          //damn - must have returned NOK -> PTC not responding?
          //continue;  //try again
        end;
      sleep(100);  
      continue;  
    end;
 if not b then
   begin
     FlagUpdate( true, CPtcNotResponding, ptcflags);
   end;
end;



function TKolPTCObject.TCPSendGeneralPTCcmd(cmd: string; Var reply: string; Timeout: longint; Var PtcFlags: TPotentioFlagSet): boolean;  //response is "OK returnval"/ "NOK returnval"  //using TCP PtcQuery command
Const
  ThisProcName =  'TCPSendGeneralPTCcmd';
Var
  repstr: string;
  b, bp, ok, bsend: boolean;
  t0: longint;
  tl: TTokenList;
begin
  Result := false;
  FlagUpdate( false, CServerNotResponding, ptcflags);
  FlagUpdate( false, CPtcNotResponding, ptcflags);
  reply := '';

  t0 := TimeDeltaTICKgetT0;
  while (TimeDeltaTICKNowMS(t0) < timeout) do
    begin
      //b := TCPSendPtcQueryLowLevel(bufin, bufout);
      bsend := TCPSendCmdRetry(cmd, repstr);
      if not bsend then
        begin
          LogWarning(ThisProcName + ': TCPSendPtcQueryLowLevel failed -> exiting');
          FlagUpdate( true, CServerNotResponding, ptcflags);
          exit;
        end;
      //ok query was send, now check if ptc responded OK
      ok := false;
      bp := ParseStrSimple(repstr, tl);
      if Length(tl)<1 then
        begin
          LogMsg(ThisProcName + ': parse bad result? len(tl)<1: ' + repstr );
          break;
        end;
      ok := (Length(tl)>=1) and (tl[0].s = 'OK');
      reply := tl[0].s;
      if ok then
        begin
          //OK!!!  be happy
          Result := true;
          break;
        end;
      sleep(100);
      continue;  
    end;
  if not ok then
   begin
     FlagUpdate( true, CPtcNotResponding, ptcflags);
   end;
end;




procedure BinStrToBuf( a: ansistring; Var buf: TKolBuffer);
Var
  i: longint;
begin
  Setlength(buf, 0);
  if length(a)=0 then exit;
  Setlength(buf, length(a));
  for i:= 0 to length(a)-1 do buf[i] := AnsiCharToByte( a[i+1] );      //ansistring  //CharToByte( a[i+1] );
end;



function TKolPTCObject.ReadRegister(regnr: word; Var buf: TKolBuffer; Var retlen: word): boolean;
begin
  Result := ReadRegisterShift(regnr, 0, buf, retlen);
end;

function TKolPTCObject.ReadRegisterShift(regnr: word; shift: byte; Var buf: TKolBuffer; Var retlen: word): boolean; //size is dynamic, adjustable, expect common size (max CBufMaxsize ) //starts nit from beginning bu from byte "shift"
Const
  procident = 'ReadRegister: ';
Var
  b, br1: boolean;
  cmdb: byte;
  s: string;
  rets, aout, acmd, apar ,av4reg,av4min,av4max : ansistring;
  tmpbufsend, tmpbufrep: TKolBuffer;
  i: longint;
begin
  Result := false;
  retlen := 0;
  if (not LockAndCheckConnectedLeaveMsg( procident )) then  exit;          //!!!!!!!!!!!!!check
  //
  //example for read reg 48:    11 00 30 01
  cmdb := $11;
  acmd := #$11;   //dec 17   =read register
  av4reg := chr( regnr div 256) + chr( regnr mod 256 );
  //apar := chr( shift ); //#01;      //!!!!???? this is not shift parameter????
  apar := #01;
  aout := acmd + av4reg + apar;
  if fPTCdebug then kolmsg( procident + 'sending '+ BinStrToPrintStr( aout ) );
  //
  BinStrToBuf( aout, tmpbufsend);
  try
    b := TCPSendPtcQuery(tmpbufsend, tmpbufrep, fTCPTimeout, fPTCFlags);
  except
     on E: exception do
        begin
           kolErrorMsg(procident + ' EXCEPTION: ' + E.message);
          //reset LOCK !!!!!!!!!!!!!
          Unlock;
          exit;
        end;
  end;
  //
  br1 := false;
  if b then
    begin
      if length( tmpbufrep )>=1 then
        begin
          //since 2016-09-30 no more echoing back the cmd = $11 at the beginning
              br1 := true;
              retlen := length( tmpbufrep );
              retlen := retlen - shift;
              if retlen<0 then retlen := 0;
              setlength(buf, retlen);
              if retlen>=1 then
                 for i:=0 to retlen-1 do buf[i] := tmpbufrep[i + shift];
        end;
    end;
  if fPTCdebug then kolmsg( '  >' + procident + 'result='+ BoolToStr(b) + ' retlen=' + IntToStr( retlen) + 'result='+ kolbuftostr(buf) + ' replylenRaw='+ IntToStr( Length( tmpbufrep ) )  +' replyRaw=' + BinStrToPrintStr( kolbuftostr( tmpbufrep ) ) );
  if not b then
    begin
      kolerrormsg(procident + ': failed!');
      Inc(fCommErrNotCorrCnt);
    end;
  Result := br1;
  Unlock;
end;


function TKolPTCObject.WriteRegister(regnr: word; Var bytes: ansistring  ): boolean;
begin
  Result := WriteRegisterShift(regnr, 0, bytes);
end;


function TKolPTCObject.WriteRegisterShift(regnr: word; shift: byte; Var bytes: ansistring  ): boolean;  //size is dynamic
Const
  procident = 'WriteRegister';
Var
  b, br1: boolean;
  c: byte;
  retlen, flags: byte;
  s: string;
  rets, aout, acmd, apar ,av4reg,av4min,av4max : ansistring;
  tmpbufsend, tmpbufrep: TKolBuffer;
begin
  Result := false;
  kolMsg('WriteRegister >' + IntToStr( regnr) + '/shift: ' +  IntToStr(shift)  + ' < val: ' +  bytes );
  if not fRegWriteEnabled then
    begin
      kolerrormsg(procident + ': RegWrite NOT enabled!');
      exit;
    end;
  if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  acmd := #$15; //#21;
  av4reg := chr( regnr div 256) + chr( regnr mod 256 );
  apar := #0 + chr( shift);
  aout := acmd + av4reg + apar + bytes;
  if fPTCdebug then kolmsg( procident + ' sending '+ BinStrToPrintStr( aout ) );
  //
  BinStrToBuf( aout, tmpbufsend);
  try
    b := TCPSendPtcQuery(tmpbufsend, tmpbufrep, fTCPTimeout, fPTCFlags);
  except
     on E: exception do
        begin
           kolErrorMsg(procident + ' EXCEPTION: ' + E.message);
          //reset LOCK !!!!!!!!!!!!!
          Unlock;
          exit;
        end;
  end;
  //

  if fPTCdebug then kolmsg( '   > ' + procident + 'result='+ BoolToStr(b) + ' len=' + IntToStr( retlen) + ' reply=' + BinStrToPrintStr( kolbuftostr( tmpbufrep ) ) );
  if not b then
    begin
      kolerrormsg(procident + ': failed!');
      Inc(fCommErrNotCorrCnt);
    end;
  Unlock;
  Result := b;
end;


function TKolPTCObject.WaitForPTCPing(timeout: longint): boolean;
var
  t0: longint;
  b: boolean;
  bufsend, bufrep: TKolBuffer;
begin
  Result := false;
  t0 := TimeDeltaTICKgetT0;
  LogMsg('  WaitForPTCPing: starting loop with ptcping');
  setlength(bufsend, 1);
  bufsend[0] := 1;  //echo
  while true and ( TimeDeltaTICKNowMS(t0)<timeout )do
    begin
      b := TCPSendPtcQuery(bufsend, bufrep, fTCPTimeout, fPTCFlags);
      if b then break;
    end;
  if b then
    begin
      LogMsg('  WaitForPTCPing: successfull, time needed(ms): ' + IntToStr(TimeDeltaTICKNowMS(t0)) );
      Result := true;
    end
  else
    begin
      LogMsg('  WaitForPTCPing: failed within timeout - time elapsed(ms): ' + IntToStr(TimeDeltaTICKNowMS(t0)) );
    end;
end;


function TKolPTCObject.PingPTC(): boolean;
Var
  b :boolean;
  bufsend, bufrep: TKolBuffer;
begin
  Result := false;
  if fNextPingTICKTime > TimeDeltaTICKgetT0 then begin Result := true; exit; end;
  if not TryToLockIfNotLeaveMsg( 'PING' ) then exit;       //not check for connected !!!!

  try
    setlength(bufsend, 1);
    bufsend[0] := 1;  //echo
    b := TCPSendPtcQuery(bufsend, bufrep, fTCPTimeout, fPTCFlags);
  except
     on E: exception do
        begin
          Result := false;
          Unlock;
          exit;
        end;
  end;
  fNextPingTICKTime :=  TimeDeltaTICKgetT0 + 20000;
  Unlock;
  Result := b;
end;


function processKolArrayOfDouble( Var kbuf: TKolBuffer; Var klen: word; Var ad: TArrayOfDouble): boolean;
Var
  i, n: longint;
begin
  Result := false;
  //will reset array size at the end, to avoid unnecessary dealocation
  n := klen div 4;
  //answer is sequence of doubles
  if (klen>=1) and (klen = n * 4) then
    begin
      SetLength(ad, n);
      for i:=0 to n-1 do
        begin
          ad[i] := BinToFloatLE( kbuf, i*4);
        end;
      Result := true;
    end
  else
    begin //error
      SetLength(ad, 0);
    end;
end;

function processKol1Byte( Var kbuf: TKolBuffer; Var klen: word; Var res: byte): boolean;
Var
  i, n: longint;
begin
  Result := false;
  res := High( byte);
  //will reset array size at the end, to avoid unnecessary dealocation
  //answer is one byte
  if klen>=1 then
    begin
      res := kbuf[0];
      Result := true;
    end;
end;


function processKolU16LE( Var kbuf: TKolBuffer; Var klen: word; Var res: word): boolean;
Var
  i, n: longint;
begin
  Result := false;
  res := High( word);
  if klen>=2 then
    begin
      res := kbuf[0] * 256 + kbuf[1] ;
      Result := true;
    end;
end;

function processKolHexString( Var kbuf: TKolBuffer; Var klen: word; Var res: string): boolean;
Var
  i, n: longint;
  u32: longword;
begin
  Result := false;
  res := '';
  //will reset array size at the end, to avoid unnecessary dealocation
  //answer is one byte
  if klen>=1 then
    begin
      u32 := BinToUint32LE( kbuf, 0);
      res := IntToHex(u32, 8);
      Result := true;
    end;
end;




function TKolPTCObject.ReadFuseSoft(Var fuserec: TKolFuseRngLimitsRec): boolean;
Const
  procident = 'ReadFuseSoft ';
Var
  b, b1: boolean;
  kbuf: TKolBuffer;
  klen: word;
  reg: byte;
  ad: TArrayOfDouble;
  i: integer;
  rrec: TRangeRecord;
begin
  InitWithNAN( fuserec );
  Result := false;
  reg := fRegConfig[ CRegLimSafe ];
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      b1 := processKolArrayOfDouble( kbuf, klen, ad);
      if b1 and (length(ad)=10) then
        begin
          i:=0;
          rrec.low := ad[i];
          rrec.high := ad[i+1];
          fuserec.V2rng := rrec;
          i:=2;
          rrec.low := ad[i];
          rrec.high := ad[i+1];
          fuserec.V4rng := rrec;
          i:=4;
          rrec.low := ad[i];
          rrec.high := ad[i+1];
          fuserec.Vrefrng := rrec;
          i:=6;
          rrec.low := ad[i];
          rrec.high := ad[i+1];
          fuserec.Irng := rrec;
        end;
    end;
  if fPTCdebug then kolmsg( procident + ' result=' +  DynArrayToStr( ad ) );
end;



function TKolPTCObject.SetFuseSoftLimits(Var fuserec: TKolFuseRngLimitsRec): boolean;
Const
  procident = 'ReadFuseSoft ';
Var
  b, b1, b2: boolean;
  reg: byte;
  i: integer;
  astr: ansistring;
  rrec: TRangeRecord;
  recreadback: TKolFuseRngLimitsRec;
begin
  InitWithNAN( fuserec );
  Result := false;

  //!!! because the v4rng is forced overwritten from other reg - has to call also upadte V4rng
  b1 := SetSafetyRangeV4(fuserec.V4rng.low, fuserec.V4rng.high);
  //
  //
  reg := fRegConfig[ CRegLimSafe ];
  //build new reg content
  astr := '';
  rrec := fuserec.V2rng;
  astr := astr + floattobinLE( rrec.low ) + floattobinLE( rrec.high );
  rrec := fuserec.V4rng;
  astr := astr + floattobinLE( rrec.low ) + floattobinLE( rrec.high );
  rrec := fuserec.Vrefrng;
  astr := astr + floattobinLE( rrec.low ) + floattobinLE( rrec.high );
  rrec := fuserec.Irng;
  astr := astr + floattobinLE( rrec.low ) + floattobinLE( rrec.high );
  //
  b := WriteRegister( reg, astr );
  //
  if not b then
    begin
      kolerrormsg(procident + ': failed write!');
      Inc(fCommErrNotCorrCnt);
    end;

  //do readback
  b2 := ReadFuseSoft(recreadback);
  //update status

  //check if changed properly

  Result := b and b1 and b2;
end;




function TKolPTCObject.ReadRegADC(Var ad: TArrayOfDouble): boolean;
Const
  procident = 'ReadRegADC ';
Var
  b: boolean;
  kbuf: TKolBuffer;
  klen: word;
  reg: byte;
begin
  Result := false;
  reg := fRegConfig[CRegADC];
  if fPTCdebug then kolmsg('>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      Result := processKolArrayOfDouble( kbuf, klen, ad);
    end;
  if fPTCdebug then kolmsg( procident + ' result=' +  DynArrayToStr( ad ) );
  If not Result then  kolMsg( procident + 'got result bad format');
end;


function TKolPTCObject.ReadRegRelayOn(Var val: byte): boolean;
Const
  procident = 'ReadRegRelayOn ';
Var
  b: boolean;
  reg: byte;
  kbuf: TKolBuffer;
  klen: word;
begin
  Result := false;
  val := 255;
  reg := fRegConfig[CRegRelayON];
  if fPTCdebug then kolmsg('>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      Result := processKol1byte( kbuf, klen, val);
    end;
  if fPTCdebug then kolmsg( procident + ' result=' +  IntToStr( val ) );
  If not Result then  kolMsg( procident + 'got result bad format');
end;



function TKolPTCObject.ReadRegSetpoint(Var val: single): boolean;
Const
  procident = 'ReadRegSetpoint ';
Var
  b, b2: boolean;
  reg: byte;
  kbuf: TKolBuffer;
  klen: word;
  ad: TArrayOfDouble;
begin
  Result := false;
  val := NAN;
  reg := fRegConfig[CRegSetpoint];
  if fPTCdebug then kolmsg('>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      b2 := processKolArrayOfDouble( kbuf, klen, ad);
      if b2 and (klen>=1) then
        begin
          val := kbuf[0];
          Result := true;
        end;
    end;
  if fPTCdebug then kolmsg( procident + ' result=' +  FloatToStr( val ) );
  If not Result then  kolMsg( procident + 'got result bad format');
end;


function TKolPTCObject.ReadRegSwFeedback(Var val: byte): boolean;
Const
  procident = 'ReadRegSwFeedback ';
Var
  b: boolean;
  reg: byte;
  kbuf: TKolBuffer;
  klen: word;
begin
  Result := false;
  val := 255;
  reg := fRegConfig[CRegSwFeedback];
  if fPTCdebug then kolmsg('>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      Result := processKol1byte( kbuf, klen, val);
    end;
  if fPTCdebug then kolmsg( procident + ' result=' +  IntToStr( val ) );
  If not Result then  kolMsg( procident + 'got result bad format');
end;


function TKolPTCObject.ReadRegProtectStatus(Var val: word): boolean;
Const
  procident = 'ReadRegProtectStatus ';
Var
  b: boolean;
  reg: byte;
  kbuf: TKolBuffer;
  klen: word;
  u16: word;
begin
  Result := false;
  val := 0;
  reg := fRegConfig[CRegProtectStatus];
  if fPTCdebug then kolmsg('>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  if b then
    begin
      u16 := 0;
      Result := processKolU16LE( kbuf, klen, u16);
      val := u16;
    end;
  if fPTCdebug then kolmsg( procident + ' result=' +  IntToStr( val ) );
end;


function TKolPTCObject.ReadRegMonI(Var ad: TArrayOfDouble): boolean;
Const
  procident = 'ReadRegMonI ';
Var
  b: boolean;
  kbuf: TKolBuffer;
  klen: word;
  reg: byte;
begin
  Result := false;
  reg := fRegConfig[CRegMonIII];
  if fPTCdebug then kolmsg('>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      Result := processKolArrayOfDouble( kbuf, klen, ad);
    end;

  if fPTCdebug then kolmsg( procident + ' result=' +  DynArrayToStr( ad ) );
  If not Result then  kolMsg( procident + 'got result bad format');
end;


function TKolPTCObject.ReadRegCRC(Var crc: string): boolean;
Const
  procident = 'ReadRegCRC ';
Var
  b: boolean;
  reg: byte;
  kbuf: TKolBuffer;
  klen: word;
  u32: longword;
begin
  Result := false;
  crc := '';
  reg := fRegConfig[CRegCRC];
  if fPTCdebug then kolmsg('>> ' + procident + ' reading reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  if b and (klen=4) then
    begin
      u32 := BinToUint32LE( kbuf, 0);
      crc := IntToHex(u32, 8);
      Result := true;
    end;
   if fPTCdebug then kolmsg( procident + '(' + booltostr( Result) + ') ' + ' crc=' +  crc );
end;


function TKolPTCObject.ReadRegLCDmsg(Var s: string): boolean;
Const
  procident = 'ReadRegLCDmsg ';
Var
  b: boolean;
  reg: byte;
  kbuf: TKolBuffer;
  klen: word;
  u32: longword;
begin
  Result := false;
  s := '';
  reg := fRegConfig[CRegLCDmsg];
  b := ReadRegister(reg,  kbuf, klen);
  if b then
    begin
      s := KolBufToStr( kbuf );
      Result := true;
    end;
  if fPTCdebug then kolmsg( procident + '(' + booltostr( Result) + ') s=' +  BinStrToPrintStr(s) );
end;



function  TKolPTCObject.ReadRegDeviceType(Var s: string ): boolean;
Const
  procident = 'ReadRegDeviceType ';
Var
  b: boolean;
  kbuf: TKolBuffer;
  klen: word;
begin
  Result := false;
  b := ReadRegister(7,  kbuf, klen);  //PTCid
  if b then s := KolBufToStr( kbuf);
  Result := b;
end;


function TKolPTCObject.GetInfo: boolean;
Const
  procident = 'GetInfo ';
Var
  b1, b2: boolean;
  s1, s2, s3: string;
  kbuf: TKolBuffer;
  klen: word;
begin
  Result := false;
  s1 := '';
  s2 := '';
  s3 := '';
  b1 :=ReadRegister(10,  kbuf, klen);  //PTCid
  if b1 then s1 := KolBufToStr( kbuf);
  b2 :=ReadRegister(9,  kbuf, klen);  //FW date
  if b2 then s2 := KolBufToStr( kbuf);
  fPTCIdString := 'Id: ' + s1 + ' Fw: '+s2;
  if fPTCdebug then kolmsg('>> ' + procident + ' result  ' +  fPTCIdString );
  Result := b1 and b2;
end;





function TKolPTCObject.ReadRegFwFuseHard(Var ad: TArrayOfDouble): boolean;
Const
  procident = 'ReadRegFwFuseHard ';
Var
  b: boolean;
  kbuf: TKolBuffer;
  klen: word;
  reg: byte;
begin
  Result := false;
  reg := fRegConfig[CRegLimHard];
  if fPTCdebug then kolmsg('>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      Result := processKolArrayOfDouble( kbuf, klen, ad);
    end;
  If not Result then  kolMsg( procident + 'got result bad format');
end;


function TKolPTCObject.ReadRegFwFuseSoft(Var ad: TArrayOfDouble): boolean;
Const
  procident = 'ReadRegFwFuseSoft ';
Var
  b: boolean;
  kbuf: TKolBuffer;
  klen: word;
  reg: byte;
begin
  Result := false;
  reg := fRegConfig[CRegLimSafe];
  if fPTCdebug then kolmsg( '>> ' + procident + ' read reg  ' +  IntToStr( reg ) );
  //
  b := ReadRegister(reg,  kbuf, klen);
  //answer is sequence of doubles
  if b then
    begin
      Result := processKolArrayOfDouble( kbuf, klen, ad);
    end;
  If not Result then  kolMsg( procident + 'got result bad format');
end;



//-----------------------------


function TKolPTCObject.ReadV4range(Var rrec: TPotentioRangeRecord): boolean;
Const
  procident = 'ReadV4range';
Var
  b: boolean;
  kbuf: TKolBuffer;
  klen: word;
  reg, shift, strt: byte;
  varlist, reslist: TStringList;
  okcnt: integer;
  valstr: string;
begin
  Result := false;
  rrec := CPTCZeroRng;
  //

  varlist := TStringList.Create;
  varlist.Capacity := 4;
  reslist := TStringList.Create;
  reslist.Capacity := 4;
  varlist.Clear;


  if fPTCVersion<=0 then
    begin

        reg := fRegConfig[CRegLimSafe];//reg := fRegConfig[CRegV4Range];
        shift :=   fV4SafeRegOffset;
        //
        if fPTCdebug then kolmsg( '>> ' + procident + ' read reg  ' +  IntToStr( reg )  + ' using  offset: ' + IntToStr( shift ) );
        //
        b := ReadRegister(reg, kbuf, klen);
        //
        if not b then
          begin
            kolerrormsg(procident + ': failed!');
            Inc(fCommErrNotCorrCnt);
          end;
        strt := shift * 4;
        if b and (klen>= strt+8) then
          begin
          rrec.low := BinToFloatLE( kbuf, strt);
          rrec.high := BinToFloatLE( kbuf, strt+4);
          Result := true;
          end;

    end
  else if fPTCVersion>=1 then
    begin
        varlist.Add('PTC.VsenseLoWarn');
        varlist.Add('PTC.VsenseHiWarn');

        b := fTCPClient.QueryGetVariables(varlist, reslist, fTCPTimeout);
        //
       okcnt := 0;
       if GetValFromSl(reslist, 'PTC.VsenseLoWarn', valstr) then  //V2    PTC.Vout
             begin
               Inc(okcnt);
               rrec.low := MyStrToFloat( valstr );
             end;
           if GetValFromSl(reslist, 'PTC.VsenseHiWarn', valstr) then
             begin
               Inc(okcnt);
               rrec.high := MyStrToFloat( valstr );
             end;
        Result := b and (okcnt>=2);

        MyDestroyAndNil( varlist);
        MyDestroyAndNil( reslist);
    end;

  if fPTCdebug then kolmsg( procident + ' result ' + BoolToStr(Result) +' len=' +  IntToStr(klen) + ' range: ' + FloatTOStr(rrec.low) +' ' + FloatTOStr(rrec.high));
end;



function TKolPTCObject.SetSafetyRangeV4(lowlim, highlim: double): boolean;
Const
  procident = 'SetSafetyRangeV4';
Var
  b, b2: boolean;
  reg, shift: byte;
  cmd, rep: string;
  acmd,av4min,av4max : ansistring;
  rngback: TRangeRecord;
begin
  Result := false;
  kolmsg('IIII ' + procident + ' (' + FloatToStr( lowlim ) + ', ' + FloatToStr( highlim )+')');

  if fPTCVersion<=0 then
    begin
            //
             //example set V4 range -0.1 1.6             //#189#204#204#205#63#204#204#205
             // data := #$03#$04;
             // Ptc_SendCmd(PByte(@data[1]), length(data), nil, nil, nil);
            reg := fRegConfig[CRegLimSafe];
            shift :=  fV4SafeRegOffset;
            //
            av4min := floattobinLE(lowlim);
            av4max := floattobinLE(highlim);
            acmd := av4min + av4max;
            //
            b := WriteRegisterShift( reg, shift, acmd );
            //
            if not b then
              begin
                kolerrormsg(procident + ': failed!');
                Inc(fCommErrNotCorrCnt);
              end;
            //store updated value
            if b then
              begin
                fRngVoltRec.low := lowlim;
                fRngVoltRec.high := highlim;
              end;
    end
  else if fPTCVersion>=1 then
    begin

      cmd := 'SET PTC.VsenseLoWarn ' + FloatToStr( lowlim ) + '; SET PTC.VsenseHiWarn ' + FloatToStr( highlim );
      b := fTCPClient.QueryCmdReliable(cmd, rep, fTCPTimeout);

            if not b then
              begin
                kolerrormsg(procident + ': failed!');
                Inc(fCommErrNotCorrCnt);
              end;
            //store updated value
            if b then
              begin
                fRngVoltRec.low := lowlim;
                fRngVoltRec.high := highlim;
              end;

    end;


  //readback the value !!! and store it
  b2 := ReadV4range( rngback );
  if not b2 then
    begin
      rngback.low := NAN;
      rngback.high := NAN;
    end;
  fRngV4SWLimit := rngback;
  fRngV4HardLimit := rngback;
  Result := b and b2;
end;



function TKolPTCObject.SetResetFuseCmd(): boolean;
Const
  procident = 'SetResetFuseCmd';
Var
  b: boolean;
  c: byte;
  reg: word;
  astr: ansistring;
  reply: string;
  flags: TPotentioFlagSet;
begin
  Result := false;
  //if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  //Unlock;   //?????? just check if available but do not lock (write register LOCKS itself )
  reg := fRegConfig[CRegProtectCmd];
//  if fPTCdebug then kolmsg( '>> ' + procident + ' write reg  ' +  IntToStr( reg ) );
//  astr := #2;
  //
//  b := WriteRegister( reg, astr );
//new method: call resetfuses cmd via ptc server

  b := TCPSendGeneralPTCcmd('resetfuse', reply, fTCPTimeout, flags);

  if not b then
    begin
      kolerrormsg(procident + ': failed! reply=' + reply);
      Inc(fCommErrNotCorrCnt);
    end;
  //here I will not update flags - in this case wait for next aquire of status
  Result := b;
end;



function TKolPTCObject.GetHWIdStr: string;
begin
  if not IsAvailable then
  begin
      Result := 'PTC not available';
      exit;
  end;
  Result := fPTCIdString; 
end;



// kolptc internal set methods






function TKolPTCObject.SetFeedback( fb: TKolPTCFeedback ): boolean;
Const
  procident = 'SetFBsource';
Var
  b: boolean;
  cmd, rep: string;
begin
  Result := false;
  if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  //V4mon sinking current workaround - Use Vref channel insterad of V4 - including Feedback!!!!!


  if fPTCVersion<1 then
    begin
        if fUseVrefInsteadOfV4 then
        begin
          if fb = CPTCFbVref then fb := CPTCFbV4
          else if fb = CPTCFbV4 then fb := CPTCFbVref;
        end;
    end
  else
    begin
        if fUseVrefInsteadOfV4 then
        begin
          //---do not change preselected fb here
          if ord(fb) = 3 then fb := TKolPTCFeedback(4);
        end;
    end;

  kolmsg('IIII Setting Feedback (' + IntToStr( ord(fb) ) + ' internal id ' + IntToStr( FBtoInternal(fb) ) +')');
  //
  cmd := 'SET Feedback ' + IntToStr( FBtoInternal(fb) );
  b := TCPSendCmdRetry(cmd, rep);
  if not b then
    begin
      kolerrormsg(procident + ': failed!');
      Inc(fCommErrNotCorrCnt);
    end;
  //TODO: WAIt for fb stabil!!!!!!!!! and to finish switching to new mode side effects - new setpoint is set internally
  Delayms(100);
  Unlock;
  //store updated value
  if b then
    begin
      fLastPTCStatus.mode := FBtoMode( fb );
      fPTCDesiredState.Feedback := fb;
    end;
  Result := b;
end;


function TKolPTCObject.SetRange( r: TKolPTCRange ): boolean;
Const
  procident = 'SetRange';
Var
  b: boolean;
  cmd, rep: string;
begin
  Result := false;
  if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  kolmsg('IIII Setting Range (' + IntToStr( ord(r) ) + ')');
  //
  cmd := 'SET Range ' + IntToStr( RangeToInternal(r) );
  b := TCPSendCmdRetry(cmd, rep);
  //
  if not b then
    begin
      kolerrormsg(procident + ': failed!');
      Inc(fCommErrNotCorrCnt);
    end;
  Unlock;
  //!!! update range reporting variable
  if b then
    begin
      fRngCurrRec := KolRngToRngRec( r );
      fPTCDesiredState.IRange := r;
    end;
  Result := b;
end;


function TKolPTCObject.SetSetpoint( sp: double ): boolean;
Const
  procident = 'SetSetpoint';
Var
  b: boolean;
  cmd, rep: string;
  adj: boolean;
begin
  Result := false;
  if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  kolmsg('IIII Setting SETPOINT ('  + FloatToStr( sp, fFormatSettings ) + ')');
  //
  //!!!!!!!!!!!!!!!!!
  //here is only place where this low level function can try to prevent overrange
  //- compare setpoint with actual range and if is out, then adjust!!!
  adj := false;
  case fLastPTCStatus.mode of
    CPotCC: begin
              if (sp < fRngCurrRec.low) then begin adj:= true; sp := fRngCurrRec.low; end;
              if (sp > fRngCurrRec.high) then begin adj:= true; sp := fRngCurrRec.high; end;
            end;
    CPotCV: begin
              if (sp < fRngVoltRec.low) then begin adj:= true; sp := fRngVoltRec.low; end;
              if (sp > fRngVoltRec.high) then begin adj:= true; sp := fRngVoltRec.high; end;
            end;
  end;
  if adj then logwarning('KolPTC SetSetpoint - SETPOINT WAS ADJUSTED because out of range - new val is: ' + FloatToStr( sp ) );
  //
  cmd := 'SET Setpoint ' + FloatToStr( sp, fFormatSettings );
  b := TCPSendCmdRetry(cmd, rep);       //tcpsendreceive
  //
  if not b then
    begin
      kolerrormsg(procident + ': failed!');
      Inc(fCommErrNotCorrCnt);
    end;
  //store updated value
  if b then
    begin
      fLastPTCStatus.setpoint := sp;
      fPTCDesiredState.Setpoint := sp;
    end;
  //TODO: WAIt for fb stabil!!!!!!!!!
  //delayms(50);
  Unlock;
  Result := b;
end;


function TKolPTCObject.SetOutputRelay( enabled: boolean): boolean;
Const
  procident = 'SetOutputRelay';
Var
  b: boolean;
  cmd, rep: string;
  val: byte;
begin
  Result := false;
  if not LockAndCheckConnectedLeaveMsg( procident ) then  exit;
  kolmsg('IIII Setting OUTPUT RELAY ('  + IfThenElse( enabled, 'ON','off') + ')');
  //
  val := IfThen(enabled, 1, 0);
  cmd := 'SET OutputEnabled ' + IntToStr( val );
  b := TCPSendCmdRetry(cmd, rep);
  //
  if not b then
    begin
      kolerrormsg(procident + ': failed!');
      Inc(fCommErrNotCorrCnt);
    end;
  //TODO: WAIt for fb stabil!!!!!!!!!
  Unlock;
  //store updated value
  if b then
    begin
      fLastPTCStatus.isLoadConnected := enabled;
      fPTCDesiredState.OutputOn := enabled;
    end;
  Result := b;
end;





procedure TKolPTCObject.SetRngV4SwLimit(rec: TRangeRecord);
begin
  if not SetSafetyRangeV4(rec.low, rec.high) then
    kolErrorMsg( 'SetRngV4SwLimit failed ');
end;



function TKolPTCObject.SetCCx( val: double; forceturnon: boolean = false; forcechangefb: boolean = false): boolean;
// TODO: turning on the connection to Load
//TODO:  check status for correct sequence, consider turnoff for changing from voltage
Const
  procident = 'SetCCx ';
Var
  Icoef, newsetp: double;
  bsp, bmode, bturnon: boolean;
begin
  Result := false;
  if not CheckConnectedLeaveMsg( procident ) then exit;
  if CDebug then kolmsg( procident +' (' + FloatToStr( val ) + ')' );
  //new setpoint if correction needed
  Icoef := 1.0; //Icoef := 0.1;    //TODO: !!!!
  newsetp := val * ICoef;

  bmode := true;
  if (fLastPTCStatus.mode <> CpotCC) or forcechangefb then //need switch fb
   begin
    if CDebug then kolmsg( procident + 'will set feedback (' + IntToStr( Ord( FBToInternal( fConstIFeedback ) ) ) + ')' );
    bmode := SetFeedback( fConstIFeedback )
   end;
  if not bmode then
      begin
       kolerrormsg(procident + ': setFB needed and failed, cannot continue');
       exit;
      end;
  //send new setpoint
  bsp := SetSetpoint( newsetp );
  if not bsp then
      begin
       kolerrormsg(procident + ': SetSP failed, cannot continue');
       exit;
      end;
  //turnon if necessary
  bturnon := true;
  if forceturnon then
   begin
    if CDebug then kolmsg( procident + 'will turn relay ON' );
    bturnon := SetOutputRelay( true );
   end;
  if not bturnon then
      begin
       kolerrormsg(procident + ': turnon requested and failed');
      end;
  Result := bmode and bsp and bturnon;
end;


function TKolPTCObject.SetCVx( val: double; forceturnon: boolean = false; forcechangefb: boolean = false): boolean;
// TODO: consider also turning on load
//TODO:  check status for correct sequence, consider turnoff for changing from voltage
Const
  procident = 'SetCVx ';
Var
  Vcoef, newsetp: double;
  bsp, bmode, bturnon: boolean;
begin
  Result := false;
  if not CheckConnectedLeaveMsg( procident ) then exit;
  if CDebug then kolmsg( procident +' (' + FloatToStr( val ) + ')' );
  //new setp
  Vcoef := 1.;    //TODO: !!!!
  newsetp := val * VCoef;
  //
  bmode := true;
  if (fLastPTCStatus.mode <> CpotCV) or forcechangefb then //need switch fb
   begin
    if CDebug then kolmsg( procident + 'will set feedback (' + IntToStr( Ord( FBToInternal( fConstUFeedback ) ) ) + ')' );
    bmode := SetFeedback( fConstUFeedback )
   end;
  if not bmode then
      begin
       kolerrormsg(procident + ': setFB needed and failed, cannot continue');
       exit;
      end;
  //send new setpoint
  bsp := SetSetpoint( newsetp );
  if not bsp then
      begin
       kolerrormsg(procident + ': SetSP failed, cannot continue');
       exit;
      end;
  //turnon if necessary
  bturnon := true;
  if forceturnon then
   begin
    if CDebug then kolmsg( procident + 'will turn relay ON' );
    bturnon := SetOutputRelay( true );
   end;
  if not bturnon then
      begin
       kolerrormsg(procident + ': turnon requested and failed');
      end;
  Result := bmode and bsp and bturnon;
end;

















//-------------------------------



function TKolPTCObject.CheckConnectedLeaveMsg( where: string ): boolean;
//helper - when not connected returns false and logs message
begin
 Result := false;
 if getIsReady and (not fTCPClient.IsReady) then
   begin
     //setIsReady( false );
     LogWarning('kolPTC:  TCP Connection  LOST! ');
     exit;
   end;
 if (not IsAvailable)  then //if (not IsAvailable) and (not fTryingConnectionFlag)  then
  begin
   //LogWarning('kolPTC checkavail -  PTC was not available!');
   exit;
  end;
 Result := true;
end;

function TKolPTCObject.LockAndCheckConnectedLeaveMsg( where: string ): boolean;
//helper - when not connected returns false and logs message
begin
 Result := false;
 if kolptclock then
   begin
     kolerrormsg(' KOLPTC-LockAndCheckIsConnected: in "' + where + '"- lock is already ENGAGED');
     exit;
   end;
 kolptclock := true;
 if not CheckConnectedLeaveMsg( where ) then
   begin
     kolptclock := false;
     exit;
   end;
 Result := true;
end;

function TKolPTCObject.TryToLockIfNotLeaveMsg( where: string ): boolean;
//helper - lock access to kolPTC communication
begin
 Result := false;
 if kolptclock then
   begin
     kolerrormsg(' KOLPTC-TryToLock: in "' + where + '"- lock is already ENGAGED');
     exit;
   end
 else kolptclock := true;
 Result := true;
end;


procedure TKolPTCObject.Unlock;
//helper - when not connected returns false and logs message
begin
  kolptclock := false;
end;







procedure TKolPTCObject.SetupRegConfig( r: TKolPTCRegisters; val: byte );
begin
  fRegConfig[r] := val;
  logmsg('TKolPTCObject.SetupRegConfig: setting reg ' + IntToStr( Ord(r) ) + ' to ' + IntToStr( val ) );
  if val = 0 then LogWarning( 'TKolPTCObject.SetupRegConfig: register val of 0 is invalid - default will be used instead');
end;

procedure TKolPTCObject.SetupChannelConfig( ch: TKolPTCChannels; val: byte );
begin
  fChannelConfig[ch] := val;
end;

procedure TKolPTCObject.MarkAsConfigured; //signal that configuration was done (maybe still check integrity) to mark configured flag
//TODO: check if all reg config is OK!
begin
  fRegConfigured := true;
  //...
end;



procedure TKolPTCObject.InitRegConfigWithDef(Var RegConf: TKolPTCRegisterConfig );
Var
 it: TKolPTCRegisters;
begin
  //to be sure, ini all reg to 0;
  for it:= Low(TKolPTCRegisters) to High(TKolPTCRegisters) do RegConf[it] := 0;
  //assign known values
  RegConf[ CRegADC ] := 19;
  RegConf[ CRegV4Range ] := 52;
  RegConf[ CRegRelayON ] := 39;
  RegConf[ CRegSetpoint ] := 40;
  RegConf[ CRegSwFeedback ] := 41;
  RegConf[ CRegProtectStatus ] := 29;
  RegConf[ CRegLimSafe ] := 31;
  RegConf[ CRegLimHard ] := 32;
  RegConf[ CRegMonIII ] := 27;
  RegConf[ CRegProtectCmd ] := 30;
  RegConf[ CRegCRC ] := 0;
  RegConf[ CRegLCDmsg ] := 54;
  RegConf[ CRegIDProduct ] := 7;
  RegConf[ CRegIDVendor ] := 8;
  RegConf[ CRegIDVer ] := 9;
  RegConf[ CRegIDstr1 ] := 10;
  RegConf[ CRegIDstr2 ] := 11;
  RegConf[ CRegFPLEDs ] := 36;
  RegConf[ CRegSwitches ] := 35;
  RegConf[ CRegAutocalib ] := 49;
  RegConf[ CRegAutorange ] := 50;
end;

function TKolPTCObject.KolRegisterToStr(r: TKolPTCRegisters ): string;
begin
  Result := 'undefined';
  case r of
    CRegADC: Result := 'RegADC';
    CRegV4Range: Result := 'RegV4Range';
    CRegRelayON: Result := 'RegRelayON';
    CRegSetpoint: Result := 'RegSetpoint';
    CRegSwFeedback: Result := 'RegSwFeedback';
    CRegProtectStatus: Result := 'RegProtectStatus';
    CRegLimSafe: Result := 'RegLimSafe';
    CRegLimHard: Result := 'RegLimHard';
    CRegMonIII: Result := 'RegMonIII';
    CRegProtectCmd: Result := 'RegProtectCmd';
    CRegCRC: Result := 'RegCRC';
    CRegLCDmsg: Result := 'RegLCDmsg';
    CRegIDProduct: Result := 'RegIDProduct';
    CRegIDVendor: Result := 'RegIDVendor';
    CRegIDVer: Result := 'RegIDVer';
    CRegIDstr1: Result := 'RegIDstr1';
    CRegIDstr2: Result := 'RegIDstr2';
    CRegFPLEDs: Result := 'RegFPLEDs';
    CRegSwitches: Result := 'RegSwitches';
    CRegAutocalib: Result := 'RegAutocalib';
    CRegAutorange: Result := 'RegAutorange';
  end;
end;


function TKolPTCObject.GenFileInfoHeaderBasic: string;
begin
  Result := '[PTC Status]'#13#10
            + 'ID=Potenciostat '+ NameLongId + #13#10
            + 'Range='+ TRangeRecordToStr( fLastPTCStatus.rangeCurrent) + '|' + TRangeRecordToStr( fLastPTCStatus.rangevoltage) +#13#10
            + 'Feedback='+ PTCModeToStr( fLastPTCStatus.Mode )+#13#10
            + 'Autocalib=NA'#13#10
            + 'AutoRange=NA'#13#10
end;

function TKolPTCObject.GenFileInfoHeaderIncludeDC: string;
begin
  Result := GenFileInfoHeaderBasic
            + 'OutputEnabled='+ BoolToStr( fLastPTCStatus.isLoadConnected )+#13#10
            + 'Feedback='+ PTCModeToStr( fLastPTCStatus.Mode )+#13#10
            + 'Setpoint='+ BoolToStr( fLastPTCStatus.isLoadConnected )+#13#10
            + 'Vout=NA'+#13#10
            + 'Vsense='+ FloatToStrF( fLastPTCdata.U , ffFixed, 4,2)+#13#10
            + 'Vref='+ FloatToStrF( fLastPTCdata.Uref , ffFixed, 4,2)+#13#10
            + 'I='+ FloatToStrF( fLastPTCdata.I , ffFixed, 4,2)+#13#10

end;


//config load save methods
procedure TKolPTCObject.LoadConfig;
Var
 regit: TKolPTCRegisters;
begin
  if fConfClient=nil then exit;
  InitRegConfigWithDef( fDefRegConfig );
  //
  //feedback selection atc.
  //buffered read, fRetryCount: byte;
  fBufferedRead := fConfClient.Load( 'BufferedRead', false );
  fRetryCount := fConfClient.Load( 'RetryCount', 3 );
  fTCPhost := fConfClient.Load( 'TCPIPHost', 'localhost' );
  fTCPport := fConfClient.Load( 'TCPIPPort', '20006' );
  fProtocolVer := fConfClient.Load( 'fProtocolVer', 1 );
  //
  fPTCVersion :=  fConfClient.Load(  'PTCVersion', 0 );
  //constufb, constifb
  fConstUFeedback := TKolPTCFeedback( fConfClient.Load(  'ConstUFeedback', 0 ) );  //internal KolPTC constant as byte
  fConstIFeedback :=  TKolPTCFeedback( fConfClient.Load(  'ConstIFeedback', 3 ) );  //internal KolPTC constant as byte
  //v4rngfrom, v4rngto
  fV4SafetyRange.low := fConfClient.Load( 'V4SafetyRngMin', -0.1);
  fV4SafetyRange.high := fConfClient.Load( 'V4SafetyRngMax', 1.4 );
  //version CRC the config is valid with (FW CRC)
  fRegVersionID := fConfClient.Load(  'RegConfigCRCVersion', 'X' );
  //
  //registers
  for regit:= Low(TKolPTCRegisters) to High(TKolPTCRegisters) do
    begin
      fRegConfig[ regit ] := fConfClient.Load( KolRegisterToStr(regit), fDefRegConfig[ regit ] );
    end;
  fRegConfigured := true;
  //
  //channels
  fChannelConfig[CChV4] := fConfClient.Load(  'CChV4',     CKolPTCFeedbackV4);
  fChannelConfig[CChVref] := fConfClient.Load(  'CChVref', CKolPTCFeedbackVRef );
  fChannelConfig[CChV2] := fConfClient.Load(  'CChV2',     CKolPTCFeedbackV2 );
  fChannelConfig[CChI] := fConfClient.Load(  'CChI',       CKolPTCFeedbackI );
  fChannelConfig[CChI10] := fConfClient.Load(  'CChI10',   CKolPTCFeedbackIx10 );
  fChannelConfig[CChSP] := fConfClient.Load(  'CChSP',     0 );
  //server
  fptcsrvwindname := fConfClient.Load(  'fptcsrvwindname',  'PTC Server' );
  fPTCServerRestartEnabled :=  fConfClient.Load(  'fPTCServerRestartEnabled',  true );
  fPTCSrvExeName := fConfClient.Load(  'fPTCSrvExeName',   'PTCServer.exe' );
  fPTCServerDefaultAppPath := fConfClient.Load(  'fPTCServerDefaultAppPath',   'C:\FCSProgramy\PTCServer' );
  //other
  fPTC1_IchannelWorkaround := fConfClient.Load(  'PTC1_IchannelWorkaround',   false );
  fUseVrefInsteadOfV4 := fConfClient.Load(  'UseVrefInsteadOfV4',   false );
  fV4SafeRegOffset := fConfClient.Load(  'V4SafeRegOffset',   2 );
  fFuseProtectUseOldStyle := fConfClient.Load(  'FuseProtectUseOldStyle',   false );
end;


procedure TKolPTCObject.SaveConfig;
begin
  if fConfClient=nil then exit;
  //feedback selection atc.
  //buffered read, fRetryCount: byte;
  fConfClient.Save( 'BufferedRead', fBufferedRead );
  fConfClient.Save( 'RetryCount', fRetryCount );
  fConfClient.Save( 'TCPIPHost', fTCPhost );
  fConfClient.Save( 'TCPIPPort', fTCPport );
  //
  fConfClient.Save(  'PTCVersion', fPTCVersion );
  //constufb, constifb
  fConfClient.Save(  'ConstUFeedback', Integer(fConstUFeedback) );  //internal KolPTC constant as byte
  fConfClient.Save(  'ConstIFeedback', Integer(fConstIFeedback) );  //internal KolPTC constant as byte
  //v4rngfrom, v4rngto
  fConfClient.Save( 'V4SafetyRngMin',fV4SafetyRange.low);
  fConfClient.Save( 'V4SafetyRngMax', fV4SafetyRange.high);
  //version CRC the config is valid with (FW CRC)
  fConfClient.Save(  'RegConfigCRCVersion', fRegVersionID );
  //registers
  fConfClient.Save( 'CRegADC',   fRegConfig[CRegADC] );
  fConfClient.Save(  'CRegRelayON',    fRegConfig[CRegRelayON]);
  fConfClient.Save(  'CRegSetpoint',     fRegConfig[CRegSetpoint] );
  fConfClient.Save(  'CRegSwFeedback',   fRegConfig[CRegSwFeedback] );
  fConfClient.Save(  'CRegProtectStatus',   fRegConfig[CRegProtectStatus] );
  fConfClient.Save(  'CRegLimSafe',     fRegConfig[CRegLimSafe] );
  fConfClient.Save(  'CRegLimHard',       fRegConfig[CRegLimHard] );
  fConfClient.Save(  'CRegMonI',      fRegConfig[CRegMonIII] );
  //channels
  fConfClient.Save(  'CChV4',    fChannelConfig[CChV4]);
  fConfClient.Save(  'CChVref', fChannelConfig[CChVref] );
  fConfClient.Save(  'CChV2',   fChannelConfig[CChV2] );
  fConfClient.Save(  'CChI',     fChannelConfig[CChI] );
  fConfClient.Save(  'CChI10',   fChannelConfig[CChI10] );
  fConfClient.Save(  'CChSP',   fChannelConfig[CChSP] );
  //other
  fConfClient.Save(  'UseVrefInsteadOfV4',   fUseVrefInsteadOfV4 );
end;


// --------------------  conversion  ----


function TKolPTCObject.FBtoInternal(fb:TKolPTCFeedback): integer;
begin
  case fb of
    CPTCFbV2: Result:= CKolPTCFeedbackV2;
    CPTCFbV4: Result:= CKolPTCFeedbackV4;
    CPTCFbVref: Result:= CKolPTCFeedbackVRef;
    CPTCFbI: Result:= CKolPTCFeedbackI;
    CPTCFbIx10: Result:= CKolPTCFeedbackIx10;
    CPTCFbIuA: Result:= CKolPTCFeedbackIuA;
    CPTCFbDO: Result:= CKolPTCFeedbackDO;
    else Result:= 0;
  end;
end;

function TKolPTCObject.InternalFBToKol(i: integer ): TKolPTCFeedback;
begin
  case i of
    CKolPTCFeedbackV2: Result := CPTCFbV2;
    CKolPTCFeedbackV4: Result:= CPTCFbV4;
    CKolPTCFeedbackVRef: Result := CPTCFbVref;
    CKolPTCFeedbackI: Result := CPTCFbI;
    CKolPTCFeedbackIx10: Result := CPTCFbIx10;
    CKolPTCFeedbackIuA: Result := CPTCFbIuA;
    CKolPTCFeedbackDO: Result := CPTCFbDO;
    else Result := CPTCFbUnknown;
  end;
end;


function TKolPTCObject.KolFBToStr( fb:TKolPTCFeedback ): string;
begin
  case fb of
    CPTCFbV2: Result:= 'V2';
    CPTCFbV4: Result:= 'V4';
    CPTCFbVref: Result:= 'Vref';
    CPTCFbI: Result:= 'I';
    CPTCFbIx10: Result:= 'Ix10';
    CPTCFbIuA: Result:= 'IuA';
    CPTCFbDO: Result:= 'DO';
    else Result:= 'Unknown';
  end;
end;

function TKolPTCObject.KolRangetoStr(r: TKolPTCRange): string;
begin
  Result:= '';
  if r=CPTCRng15A then Result:= '15 A'
  else if r=CPTCRng500mA then Result:= '200 mA';
end;


function TKolPTCObject.RangeToInternal(r: TKolPTCRange): integer;
begin
  Result:= 0;
  if r=CPTCRng15A then Result:= CKolPTCRangeR10mOhm
  else if r=CPTCRng500mA then Result:= CKolPTCRangeR1Ohm;
end;






function TKolPTCObject.InternalRngToKol(i: integer ): TKolPTCRange;
begin
  Result := High(TKolPTCRange);
  if i = CKolPTCRangeR10mOhm  then Result:= CPTCRng15A
  else if i = CKolPTCRangeR1Ohm then Result:= CPTCRng500mA;
end;


function TKolPTCObject.FBtoMode(fb:TKolPTCFeedback): TPotentioMode;
begin
  Result := CPotERR;
  if fPTCVersion<1 then
    begin
        if (fb = CPTCFbV2) or (fb = CPTCFbV4) or   (fb = CPTCFbVref) then Result := CPotCV;
        if (fb = CPTCFbI) or (fb =  CPTCFbIx10 ) then  Result := CPotCC;
    end
  else
    begin
      if Ord(fb)=0 then Result := CPotCC
      else if (Ord(fb)>=1) and (Ord(fb)<=4) then  Result := CPotCV;
    end;
end;


function TKolPTCObject.KolRngToRngRec( kr: TKolPTCRange): TPotentioRangeRecord;
begin
  Result := CPTCZeroRng;
  case kr of
    CPTCRng15A: begin
                  Result.low := -15.0;
                  Result.high := 15.0;
                end;
    CPTCRng500mA: begin
                  Result.low := -0.5;
                  Result.high := 0.5;
                  end;
  end;
end;


procedure TKolPTCObject.WriteRetryCount( c: byte );   //make sure c is at least 1
begin
  if c<1 then c := 1;
  fRetryCount := c;
end;

procedure TKolPTCObject.setPTCdebug(b: boolean);
begin
  fPTCdebug := b;
  if fTCPClient<>nil then fTCPClient.Debug := b
end;

procedure TKolPTCObject.LeaveLogMsg(a: string);
begin
  if flog=nil then exit;
  fLog.LogMsg(a);
end;

procedure TKolPTCObject.DebugLeaveLogMsg(a: string; force: boolean = false);
begin
  if fPTCdebug or force then LeaveLogMsg(a);
end;

procedure TKolPTCObject.kolmsg(s: string); //set lastmsg and log it at the same time
begin
  logmsg('KolPTC: '+ s);
end;

procedure TKolPTCObject.kolerrormsg(s: string); //set lastmsg and log it at the same time
begin
  if GlobalConfig.initflag then logmsg('KolPTC(error during init): '+ s)       //do not report error if initflag
  else logerror('KolPTC: '+ s);
end;


function TKolPTCObject.kolAssert(ex: boolean; s: string): boolean; //if ex is FALSE leaves warning message; returns true if Assert OK
begin
  Result := ex;
  if not ex then logmsg('KolPTC-Assert failed: '+ s);
end;



function kolbuftostr(Var buf: TKolBuffer ): string;
Var i, l: longint;
begin
  Result := '';
  l := Length(buf);
  if l=0 then exit;
  for i:=0 to l-1 do Result := Result + chr( buf[i] );
end;


//--------------------------------
//   DLL Handling
//--------------------------------

procedure TKolPTCObject.ConfigureTCPIP( host, port: string);
begin
  fTCPClient.ConfigureTCP('localhost', '20006');
  fTCPClient.Open;
  LeaveLogMsg( 'in ConfigureTCP - server is ' + fTCPClient.ConfHost + ':' + fTCPClient.ConfPort);
end;

//--------------------------------


function RetryCallUntilOK( Pfn: PBoolFunc; argc: byte; ArgArray: TArgArray; retryc: byte): boolean;
//pfn: pointer to function that returns boolean (interface functions inptc.dll)
//tries to repeat call until geting true as result- in order to overcome communication errors and so
Var
  b: boolean;
begin
  Result := false;
  if Pfn=nil then exit;
  while retryc>0 do
    begin
    end;
end;






procedure CopyDynArrayToStatic( Var adyn: TArrayOfDouble; Var astat: TStaticArrayOfDouble; Var statlen: byte);
Var
 i,n: longint;
begin
  n := Length(adyn);
  if n>CKolPTCStaticArraySize then n :=  CKolPTCStaticArraySize;
  statlen := n;
  if n=0 then exit;
  for i:=0 to n-1 do astat[i] := adyn[i];
end;




procedure InitWithNAN( Var rec: TKolFuseRngLimitsRec);
begin
  InitWithNaN( rec.V2rng );
  InitWithNaN( rec.V4rng );
  InitWithNaN( rec.Vrefrng );
  InitWithNaN( rec.Irng );
end;



//---------------------------trash -----

function TKolPTCObject.GetDataBuffered(Var Rec: TPotentioRec; Var Status: TPotentioStatus): boolean;
Var
  oldb: boolean;
begin
  oldb := FBufferedRead;
  FBufferedRead := true;
  if CDebug then kolmsg('in getdata buffered');
  Result := AquireDataStatus(Rec, Status);
  if CDebug then kolmsg('out getdata buffered');
  FBufferedRead := oldb;
end;


end.
