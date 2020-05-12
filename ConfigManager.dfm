object GlobalConfig: TGlobalConfig
  Left = 345
  Top = 295
  Width = 1198
  Height = 435
  Caption = 'GlobalConfig'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnHide = FormHide
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object Label38: TLabel
    Left = 5
    Top = 109
    Width = 65
    Height = 18
    AutoSize = False
    Caption = 'Station ID'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
    Layout = tlCenter
  end
  object Label1: TLabel
    Left = 257
    Top = 109
    Width = 120
    Height = 18
    AutoSize = False
    Caption = 'Global File counter'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object LaGlobPath: TLabel
    Left = 11
    Top = 5
    Width = 133
    Height = 18
    AutoSize = False
    Caption = 'Global App Dir'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
    Layout = tlCenter
  end
  object Label2: TLabel
    Left = 8
    Top = 58
    Width = 152
    Height = 13
    Caption = 'new home dir (without last slash)'
  end
  object Label3: TLabel
    Left = 13
    Top = 290
    Width = 111
    Height = 18
    AutoSize = False
    Caption = 'Global App Path'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
    Layout = tlCenter
  end
  object Label4: TLabel
    Left = 7
    Top = 37
    Width = 143
    Height = 17
    AutoSize = False
    Caption = 'Global DATA home Dir'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
    Layout = tlCenter
  end
  object BuCancel: TButton
    Left = 8
    Top = 185
    Width = 409
    Height = 41
    Caption = 'Hide'
    TabOrder = 0
    OnClick = BuCancelClick
  end
  object BuSaveFileCnt: TButton
    Left = 400
    Top = 151
    Width = 89
    Height = 17
    Caption = 'Save changes'
    TabOrder = 1
    OnClick = BuSaveFileCntClick
  end
  object PanGlobAppDir: TPanel
    Left = 152
    Top = 5
    Width = 791
    Height = 18
    BorderStyle = bsSingle
    Caption = 'Pan'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentColor = True
    ParentFont = False
    TabOrder = 2
  end
  object ENewFileCnt: TEdit
    Left = 384
    Top = 128
    Width = 97
    Height = 21
    TabOrder = 3
  end
  object EnewStaid: TEdit
    Left = 64
    Top = 128
    Width = 153
    Height = 21
    TabOrder = 4
  end
  object PanStaId: TPanel
    Left = 72
    Top = 109
    Width = 129
    Height = 18
    BorderStyle = bsSingle
    Caption = 'Pan'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentColor = True
    ParentFont = False
    TabOrder = 5
  end
  object PanGlobFileCnt: TPanel
    Left = 384
    Top = 109
    Width = 129
    Height = 18
    BorderStyle = bsSingle
    Caption = 'Pan'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentColor = True
    ParentFont = False
    TabOrder = 6
  end
  object BuSaveHomeDir: TButton
    Left = 658
    Top = 54
    Width = 90
    Height = 17
    Caption = 'Save changes'
    TabOrder = 7
    OnClick = BuSaveHomeDirClick
  end
  object PanAppPath: TPanel
    Left = 154
    Top = 290
    Width = 783
    Height = 18
    BorderStyle = bsSingle
    Caption = 'Pan'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentColor = True
    ParentFont = False
    TabOrder = 8
  end
  object PanglobDataDir: TPanel
    Left = 161
    Top = 37
    Width = 776
    Height = 17
    BorderStyle = bsSingle
    Caption = 'Pan'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentColor = True
    ParentFont = False
    TabOrder = 9
  end
  object ENewDataDir: TEdit
    Left = 181
    Top = 56
    Width = 470
    Height = 21
    TabOrder = 10
  end
  object BuSaveId: TButton
    Left = 80
    Top = 145
    Width = 89
    Height = 17
    Caption = 'Save changes'
    TabOrder = 11
    OnClick = BuSaveIdClick
  end
  object Timer1: TTimer
    OnTimer = Timer1Timer
    Left = 8
  end
end
