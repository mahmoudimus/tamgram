changequote(`[[', `]]')
builtins := signing, hashing, asymmetric-encryption, xor

apred NEq/2 //inequality
apred Eq/2
fun f/2 //key derivation function
fun MAC/2 //cipher-based MACs
fun MAC_arpc/2
fun p8/1 //padding function, used in ARPC computation w/ Method 1

pred Send/4
pred Recv/4
apred Once/1
pred !Value/2
pred !ATC/1
pred !SDADFormat/2

//=============== Non-DY Channel ==============//
//secure channel for terminal-bank communication
process Terminal_Bank_Network =
    [ Send(S, R, channelID, msg) ]-->[ Recv(S, R, channelID, msg) ]

//=================== Pools ==================//
//any given amount is always either Low or High, thus the usage of Once(...)
process Generate_Amount_Low =
    [ ]--[ Once(<$amount, "Amount">) ]->[ !Value($amount, "Low") ]

process Generate_Amount_High =
    [ ]--[ Once(<$amount, "Amount">) ]->[ !Value($amount, "High") ]

//the transaction counter
process Generate_ATC =
    [ Fr(~ATC) ]-->[ !ATC(~ATC), Out(~ATC) ]

//the 2-option choice of the SDAD format in Visa
process Generate_SDAD_Format_Visa =
    [ ]--> [ !SDADFormat("05", "TC"), !SDADFormat("95", "ARQC") ]

apred Role/2
pred !LtkCA/2
pred !CertCA/2

//=============== PKI and Bank setup ==============//
//CA setup
//Actor of this rule is: $CA
process Create_CA =
    [ Fr(~privkCA) ]
  --
    let pubkCA = pk(~privkCA) in
    let cont = <"01", $CA, pubkCA, $CA> in
    let cert = <cont, sign(cont, ~privkCA)> in
    [ Once($CA),
      Role($CA, "CA") ]->
    [ !LtkCA($CA, ~privkCA),
      !CertCA($CA, cert),
      Out(pubkCA)
    ]

pred !LtkBank/2
pred !CertBank/2
pred !IssuingCA/2

//Bank setup
//Actor of this rule is: $CA 
process Create_Bank =
    [ Fr(~privkBank),
      !LtkCA($CA, ~privkCA) ]
  --
    let pubkBank = pk(~privkBank) in
    let cont = <"02", $Bank, pubkBank, $CA> in
    let cert = <cont, sign(cont, ~privkCA)> in
    [ Once($Bank),
      Role($Bank, "Bank") ]->
    [ !LtkBank($Bank, ~privkBank),
      !CertBank($Bank, cert),
      !IssuingCA($Bank, $CA),
      Out(pubkBank)
    ]

apred Compromise/1
pred !IssuingBank/2
pred !Shk/2

//=========== Compromise rules =============//
process Compromise_CA =
    [ !LtkCA($CA, ~privkCA) ]
  --[ Compromise($CA) ]->
    [ Out(~privkCA)]

process Compromise_Bank =
    [ !LtkBank($Bank, ~privkBank) ]
  --[ Compromise($Bank) ]->
    [ Out(<$Bank, ~privkBank>) ]

pred !LtkCard/2

process Compromise_Card =
    [ !LtkCard(~PAN, ~privkCard) ]
  --[ Compromise(~PAN) ]->
    [ Out(<~PAN, ~privkCard>) ]

process Compromise_Bank_Card_ShK =
    [ !IssuingBank(~PAN, $Bank),
      !Shk(~PAN, ~MK) ]
  --[ Compromise($Bank), Compromise(~PAN) ]->
    [ Out(~MK) ]

apred SecretPIN/1
apred Honest/1

apred SecretPAN/1
apred SecretMK/1

pred Set_PIN/4

pred !Entered_PIN/2
pred !PIN/2

//=============== PIN ==================//
process pSet_PIN =
    [ Fr(~PIN),
      Set_PIN(~PAN, CVM, $CA, $Bank)
    ]
  --[ NEq(CVM, "NoPIN"),
      SecretPIN(~PIN),
      Honest($CA), Honest($Bank), Honest(PAN) ]->
    [ !PIN(PAN, ~PIN),
      !Entered_PIN(PAN, ~PIN),//legitimate cardholder enters the PIN
      !Entered_PIN(PAN, "WrongPIN")//attacker enters a wrong PIN
    ]

pred !AID/2
apred OneCard/0
apred Running/3

///////////////////////////////////////////////////
//                 Mastercard                    //
///////////////////////////////////////////////////
pred Set_Records/6

pred !AIP/2
pred !Records/2
apred SecretPrivkCard/1

process pSet_Records =
  choice {
    { "Set_Records_SDA":
        [ Set_Records(~PAN, ~expDate, $CA, certBank, SSAD, CVM),
          !AIP(~PAN, <"SDA", _furtherData>) ]
      -->
        [ !Records(PAN, <PAN, expDate, $CA, certBank, SSAD, CVM>) ]
    };
    { "Set_Records_NotSDA":
        [ Set_Records(~PAN, ~expDate, $CA, certBank, SSAD, CVM),
          Fr(~privkCard),
          !AIP(~PAN, AIP),
          !IssuingBank(~PAN, $Bank),
          !LtkBank($Bank, ~privkBank) ]
      --
        let pubkCard = pk(~privkCard) in
        let cont = <"04", PAN, pubkCard, $Bank, CVM, AIP> in
        let certCard = <cont, sign(cont,~privkBank)> in
        [ NEq(fst(AIP), "SDA"),
          SecretPrivkCard(~privkCard),
          Honest($CA), Honest($Bank), Honest(PAN) ]->
        [ Out(pubkCard),
          !LtkCard(PAN, ~privkCard),
          !Records(PAN, <PAN, expDate, $CA, certBank, certCard, CVM>) ]
    };
  }

//Card setup
//Actor of this rule is: $Bank
process Create_Card =
    [ Fr(~PAN),
      Fr(~expDate),
      Fr(~MK),
      !LtkBank($Bank, ~privkBank),
      !CertBank($Bank, certBank),
      !IssuingCA($Bank, $CA),
      In(<auth, CVM>)
    ]
  --
    let AIP = <auth, $furtherData> in
    let SSAD = sign(<"03", ~PAN, ~expDate, AIP>, ~privkBank) in
    [ Role(~PAN, "Card"),
      SecretPAN(~PAN),
      SecretMK(~MK),
      Honest($CA), Honest($Bank), Honest(~PAN) ]->
    [ !AIP(~PAN, AIP),
      !AID(~PAN, "Mastercard"),
      !Shk(~PAN, ~MK),
      !IssuingBank(~PAN, $Bank),
      Set_Records(PAN, expDate, $CA, certBank, SSAD, CVM),
      Set_PIN(PAN, CVM, $CA, $Bank)
    ]

process Card =
  "Card_Responds_To_GPO":
    [ In(<"GET_PROCESSING_OPTIONS", PDOL>),
      !AIP(~PAN, AIP),
      !AID(~PAN, "Mastercard"),
      !ATC(ATC) ]
  --[ OneCard(),
      Once(<PAN, ATC, "Card">) ]->
    [ Out(<AIP, "AFL">),
      'PAN := PAN,
      'PDOL := PDOL,
      'ATC := ATC,
    ];

  /* Card_Responds_To_ReadRecord_* */
  choice {
    { "Card_Responds_To_ReadRecord_NotDDA":
        [ !AIP('PAN, AIP),
          !Records('PAN, records),
          In(<"READ_RECORD", "AFL">) ]
      --[ NEq(fst(AIP), "DDA") ]->
        [ Out(records) ]
    };
    { "Card_Responds_To_ReadRecord_DDA":
        [ !Records('PAN, records),
          !AIP('PAN, <"DDA", _furtherData>),
          In(<"READ_RECORD", "AFL">) ]
      -->
        [ Out(records) ];

      "Card_Responds_To_InternalAuthenticate":
        [ Fr(~nc),
          !LtkCard('PAN, ~privkCard),
          In( <"INTERNAL_AUTHENTICATE", DDOL> ) ]
      -->
        [ Out( <~nc, sign(<"05", ~nc, DDOL>, ~privkCard)> ),
        ]
    };
  };

  /* Card_Responds_To_GenerateAC_* */
  choice {
    { "Card_Responds_To_GenerateAC_NoCDA":
        [ !AIP('PAN, AIP),
          !Shk('PAN, ~MK),
          !IssuingBank('PAN, $Bank),
          In(< "GENERATE_AC", CID, "NoCDA", <"TVR", CVM, "HHMMSS"> as CDOL1 >) ]
      --
        let X = <'PDOL, CDOL1> in
        let IAD = <"IAD", CID> in
        let AC = MAC(f(~MK, 'ATC), <X, AIP, 'ATC, IAD>) in
        let transaction = <'PAN, AIP, CVM, X, 'ATC, AC, IAD> in
        [
          Running('PAN, "Terminal", <"Card", "Terminal", transaction>),
          Running('PAN, $Bank, <"Card", "Bank", transaction>) ]->
        [ Out(<CID, 'ATC, AC, IAD>) ]
    };
    { "Card_Responds_To_GenerateAC_CDA":
        [ 'PDOL cas <amount, country, currency, date, type, UN>,
          !LtkCard('PAN, ~privkCard),
          !AIP('PAN, <"CDA", _furtherData> as AIP),
          !Shk('PAN, ~MK),
          !IssuingBank('PAN, $Bank),
          Fr(~nc),
          In(< "GENERATE_AC", CID, "CDA", <"TVR", CVM, "HHMMSS"> as CDOL1 >) ]
      --
        let X = <'PDOL, CDOL1> in
        let IAD = <"IAD", CID> in
        let AC = MAC(f(~MK, 'ATC), <X, AIP, 'ATC, IAD>) in
        let T' = h(<X, CID, 'ATC, AC, IAD>) in
        let SDAD = sign(<"05", ~nc, CID, AC, T', UN>, ~privkCard) in
        let transaction = <'PAN, AIP, CVM, X, 'ATC, AC, IAD> in
        [ Running('PAN, "Terminal", <"Card", "Terminal", transaction>),
          Running('PAN, $Bank, <"Card", "Bank", transaction>) ]->
        [ Out(<CID, 'ATC, AC, <~nc, SDAD>, IAD>) ]
    };
  }

pred !ExpirationDate/2
pred !Records_Visa/5

process Create_Card_Visa =
    [ Fr(~PAN),
      Fr(~expDate),
      Fr(~privkCard),
      Fr(~MK),
      !LtkBank($Bank, ~privkBank),
      !CertBank($Bank, certBank),
      !IssuingCA($Bank, $CA)
    ]
  --
    let pubkCard = pk(~privkCard) in
    let cont = <"04", ~PAN, pubkCard, $Bank> in
    let certCard = <cont, sign(cont, ~privkBank)> in
    [ Role(~PAN, "Card"),
      SecretPAN(~PAN),
      SecretMK(~MK),
      SecretPrivkCard(~privkCard),
      Honest($CA), Honest($Bank), Honest(~PAN) ]->
    [ !LtkCard(~PAN, ~privkCard),
      !AID(~PAN, "Visa"),
      Out(pubkCard),
      !ExpirationDate(~PAN, ~expDate),
      !Shk(~PAN, ~MK),
      !IssuingBank(~PAN, $Bank),
      !Records_Visa(~PAN, ~expDate, $CA, certBank, certCard),
      Set_PIN(~PAN, "OnlinePIN", $CA, $Bank)
    ]

process Card_Visa =
  /* Card_Responds_To_GPO_*_Visa */
  choice {
    { "Card_Responds_To_GPO_EMV_Visa":
        [ In(<"GET_PROCESSING_OPTIONS",
             <<acType, CVM>, amount, country, currency, date, type, UN> as PDOL>),
          !Shk(~PAN, ~MK),
          !AID(~PAN, "Visa"),
          !ExpirationDate(~PAN, ~expDate),
          !IssuingBank(~PAN, $Bank),
          !ATC(ATC) ]
      --
        let track2ED = <PAN, ~expDate> in
        let CID = "ARQC" in
        let CTQ = CVM in
        let IAD = <"IAD", CID> in
        let AIP = <"EMV", $furtherData> in
        let AC = MAC(f(~MK, ATC), <PDOL, AIP, ATC, IAD>) in
        let transaction = <PAN, AIP, CTQ, PDOL, ATC, AC, IAD> in
        [ OneCard(),
          Once(<PAN, ATC, "Card">),
          NEq(CVM, "CDCVM"), //received CVM must be either OnlinePIN or NoPIN
          //place the running facts already, otherwise auth will trivially fail 
          Running(PAN, "Terminal", <"Card", "Terminal", transaction>),
          Running(PAN, $Bank, <"Card", "Bank", transaction>) ]->
        [ Out(< AIP, "AFL", track2ED, IAD, AC, CID, ATC, CTQ >),
          'PAN := PAN,
          'AIP := AIP,
          'PDOL := PDOL,
          'ATC := ATC,
          'AC := AC,
          'CID := CID,
          'CTQ := CTQ,
          'IAD := IAD
        ]
    };
    { "Card_Responds_To_GPO_DDA_Visa":
        [ In(<"GET_PROCESSING_OPTIONS",
             <<CID, CVM>, amount, country, currency, date, type, UN> as PDOL>),
          !Shk(~PAN, ~MK),
          !AID(~PAN, "Visa"),
          !ExpirationDate(~PAN, ~expDate),
          !ATC(ATC) ]
      --[ OneCard(),
          Once(<PAN, ATC, "Card">),
          NEq(CVM, "CDCVM")//received CVM must be either OnlinePIN or NoPIN
        ]->
        let track2ED = <PAN, ~expDate> in
        let IAD = <"IAD", CID> in
        let AIP = <"DDA", $furtherData> in
        let AC = MAC(f(~MK, ATC), <PDOL, AIP, ATC, IAD>) in
        let CTQ = CVM in//encoded this way for simplicity
        [ Out(< AIP, "AFL", track2ED, IAD, AC, CID, ATC, CTQ >),
          'PAN := PAN,
          'AIP := AIP,
          'PDOL := PDOL,
          'ATC := ATC,
          'AC := AC,
          'CID := CID,
          'CTQ := CTQ,
          'IAD := IAD
        ]
    };
  };

  /* Card_Responds_To_ReadRecord_* */
  choice {
    { "Card_Responds_To_ReadRecord_EMV_Visa":
        [ 'AIP cas <"EMV", _furtherData>,
          !Records_Visa('PAN, ~expDate, $CA, certBank, certCard),
          In(< "READ_RECORD", "AFL" >) ]
      -->
        [ Out(<'PAN, ~expDate>) ]
    };
    { "Card_Responds_To_ReadRecord_DDA_Visa":
        [ 'AIP cas <"DDA", _furtherData>,
          'PDOL cas <TTQ, amount, country, currency, date, type, UN>,
          !Records_Visa('PAN, ~expDate, $CA, certBank, certCard),
          Fr(~nc),
          !LtkCard('PAN, ~privkCard),
          !SDADFormat(format, 'CID),
          !IssuingBank('PAN, $Bank),
          In(< "READ_RECORD", "AFL" >) ]
      --
        ifdef([[flFix]],
        [[let d = <format, nc, 'CID, 'AC, 'PDOL, 'ATC, 'CTQ, UN, 'IAD, 'AIP> in]],
        [[let d = <format, 'ATC, UN, amount, "CHF", ~nc, 'CTQ, 'AIP> in]]
        )
        let SDAD = sign(d, ~privkCard) in
        let transaction = <'PAN, 'AIP, 'CTQ, 'PDOL, 'ATC, 'AC, 'IAD> in
        [ Running('PAN, "Terminal", <"Card", "Terminal", transaction>),
          Running('PAN, $Bank, <"Card", "Bank", transaction>) ]->
        [ Out(< 'PAN, ~expDate, $CA, certBank, certCard, ~nc, 'CTQ, SDAD >) ]
    };
  }

apred OneTerminal/0
apred Compatible_CID_acType/2
apred Compatible_CID_CVM/2

apred TerminalAccepts/1
apred Commit/3

process Terminal =
  //============== Initialization ====================//
  //for simplicity, SELECT exchanges are ignored
  "Terminal_Sends_GPO":
    [ Fr(~UN),
      !Value($amount, value) ]
  --
    let date = "YYMMDD" in
    let type = "Purchase" in
    let currency = "CHF" in
    let country = "Switzerland" in
    let PDOL = <$amount, country, currency, date, type, ~UN> in
    [ OneTerminal(),
      Role($Terminal, "Terminal") ]->
    [ Out(<"GET_PROCESSING_OPTIONS", PDOL>),
      'PDOL := PDOL
    ];

  //============== Read Records ====================//
  "Terminal_Sends_ReadRecord":
    [ In(<AIP, "AFL">) ]
  -->
    [ Out(<"READ_RECORD", "AFL">),
      'AIP := AIP
    ];

  /* Terminal_Receives_Records_* */
  choice {
    //============== Offline Data Authentication ====================//
    //SDA
    { "Terminal_Receives_Records_SDA":
        [ 'AIP cas <"SDA", _>,
          In(<~PAN, expDate, $CA,
             <<"02", $Bank, pubkBank, $CA>, sign2>,
             SSAD, CVM>
             as records),
          !IssuingCA($Bank, $CA),
          !CertCA($CA, <<"01", $CA, pubkCA, $CA>, sign1>) ]
      --
        [ //verify CA's cert (this is possibly not needed)
          Eq( verify(sign1, <"01", $CA, pubkCA, $CA>, pubkCA), true()),
          //verify the bank's cert
          Eq( verify(sign2, <"02", $Bank, pubkBank, $CA>, pubkCA), true()),
          //verify the SSAD
          Eq( verify(SSAD, <"03", ~PAN, expDate, 'AIP>, pubkBank), true())
        ]->
        [ 'PAN := PAN,
          'pubkBank := pubkBank,
          'pubkCard := "Null",
          'CVM := CVM,
        ]
    };
    //CDA
    { "Terminal_Receives_Records_CDA":
        [ 'AIP cas <"CDA", _>,
          In(<~PAN, expDate, $CA,
             <<"02", $Bank, pubkBank, $CA>, sign2>,
             <<"04", ~PAN, pubkCard, $Bank, CVM, 'AIP>, sign3>,
             CVM>
             as records),
          !IssuingCA($Bank, $CA),
          !CertCA($CA, <<"01", $CA, pubkCA, $CA>, sign1>) ]
      --[
          Eq( verify(sign1, <"01", $CA, pubkCA, $CA>, pubkCA), true()),
          Eq( verify(sign2, <"02", $Bank, pubkBank, $CA>, pubkCA), true()),
          Eq( verify(sign3, <"04", ~PAN, pubkCard, $Bank, CVM, 'AIP>, pubkBank), true())
        ]->
        [ 'PAN := PAN,
          'pubkBank := pubkBank,
          'pubkCard := pubkCard,
          'CVM := CVM
        ]
    };
    //DDA
    { "Terminal_Receives_Records_DDA":
        [ 'AIP cas <"DDA", _>,
          !IssuingCA($Bank, $CA),
          In(<~PAN, expDate, $CA,
             <<"02", $Bank, pubkBank, $CA>, sign2>,
             <<"04", ~PAN, pubkCard, $Bank, CVM, 'AIP>, sign3>,
             CVM>
             as records),
          !CertCA($CA, <<"01", $CA, pubkCA, $CA>, sign1>) ]
      --[
          Eq( verify(sign1, <"01", $CA, pubkCA, $CA>, pubkCA), true()),
          Eq( verify(sign2, <"02", $Bank, pubkBank, $CA>, pubkCA), true()),
          Eq( verify(sign3, <"04", ~PAN, pubkCard, $Bank, CVM, 'AIP>, pubkBank), true())
        ]->
        [ 'PAN := PAN,
          'pubkBank := pubkBank,
          'pubkCard := pubkCard,
          'CVM := CVM
        ];

      "Terminal_Sends_InternalAuthenticate":
        [ 'PDOL cas <$amount, country, currency, date, type, ~UN> ]
      -->
        let DDOL = ~UN in
        [ Out( <"INTERNAL_AUTHENTICATE", DDOL> ),
        ];

      "Terminal_Receives_InternalAuthenticate_Response":
        [ 'PDOL cas <$amount, country, currency, date, type, ~UN>,
          In(<nc, SDAD>)
        ]
      --[ Eq( verify(SDAD, <"05", nc, ~UN>, 'pubkCard), true()) ]->
        []
    };
  };

  //============== Cardholder Verification ===================//
  /* Terminal_Processes_CVM_* */
  choice {
    //No PIN
    { "Terminal_Processes_CVM_NoPIN":
        [ 'PDOL cas <$amount, country, currency, date, type, ~UN>,
          !Value($amount, "Low") ]
      -->
        [ 'CVM := "NoPIN",
          'encPIN := "Null",
          'supportedCVM := 'CVM
        ]
    };
    //Online PIN
    { "Terminal_Processes_CVM_OnlinePIN":
        [ 'CVM cas "OnlinePIN",
          'PDOL cas <$amount, country, currency, date, type, ~UN>,
          !Entered_PIN('PAN, PIN),
          !Value($amount, "High") ]
      -->
        [ 'CVM := "OnlinePIN",
          'encPIN := aenc(PIN, 'pubkBank),
          'supportedCVM := "OnlinePIN",
        ]
    };
    //On-device CVM
    { "Terminal_Processes_CVM_ODCVM":
        [ 'PDOL cas <$amount, country, currency, date, type, ~UN>,
          'AIP cas <auth, <"ODCVM", furtherData2>>,
          !Value($amount, "High") ]
      -->
        [ 'CVM := "ODCVM",
          'encPIN := "Null",
          'supportedCVM := 'CVM
        ]
    };
  };

  //============== Application Cryptogram =================//
  /* Terminal_Sends_GenerateAC_* */
  choice {
    { "Terminal_Sends_GenerateAC_NoCDA":
        [ In(acType) ]
      --
        let CDOL1 = <"TVR", 'CVM, "HHMMSS"> in
        let X = <'PDOL, CDOL1> in
        [ NEq(fst('AIP), "CDA") ]->
        [ Out(< "GENERATE_AC", acType, "NoCDA", CDOL1 >),
          'acType := acType,
          'X := X,
        ];

      "Terminal_Receives_AC_NoCDA":
        [ In(<CID, ATC, AC, IAD>),
          Fr(~channelID) ]
      --
        let transaction = <'PAN, 'AIP, 'CVM, 'X, ATC, AC, IAD> in
        [ Compatible_CID_acType(CID, 'acType),
          Compatible_CID_CVM(CID, 'CVM),
          Running($Terminal, $Bank, <"Terminal", "Bank", transaction>) ]->
        [ 'nc := "Null",
          'CID := CID,
          'transaction := transaction,
          'channelID := channelID,
          Send($Terminal, $Bank, <~channelID, "Mastercard", "1">,
            <transaction, 'encPIN>) ]
    };
    { "Terminal_Sends_GenerateAC_CDA":
        [ In(acType),
          'AIP cas <"CDA", _furtherData>
        ]
      -->
        let CDOL1 = <"TVR", 'CVM, "HHMMSS"> in
        let X = <'PDOL, CDOL1> in
        [ Out(< "GENERATE_AC", acType, "CDA", CDOL1 >),
          'acType := acType,
          'X := X
        ];

      "Terminal_Receives_AC_CDA":
        [ In(<CID, ATC, AC, <nc, SDAD>, IAD>),
          'X cas <<$amount, country, currency, date, type, ~UN> as PDOL, _>,
          Fr(~channelID) ]
      --
        let transaction = <'PAN, 'AIP, 'CVM, 'X, ATC, AC, IAD> in
        let T' = h(<'X, CID, ATC, AC, IAD>) in
        [ Compatible_CID_acType(CID, 'acType),
          Compatible_CID_CVM(CID, 'CVM),
          Eq( verify(SDAD, <"05", nc, CID, AC, T', ~UN>, 'pubkCard), true() ),
          Running($Terminal, $Bank, <"Terminal", "Bank", transaction>) ]->
        [ 'nc := nc,
          'CID := CID,
          'transaction := transaction,
          'channelID := channelID,
          Send($Terminal, $Bank, <~channelID, "Mastercard", "1">,
            <transaction, 'encPIN>) ]
    };
  }dnl
ifdef([[flMastercard]],
[[;
ifdef([[flSDA]], [[define([[_AIP]], [[<"SDA", _furtherData>]])]])dnl
ifdef([[flDDA]], [[define([[_AIP]], [[<"DDA", _furtherData>]])]])dnl
ifdef([[flCDA]], [[define([[_AIP]], [[<"CDA", _furtherData>]])]])dnl
ifdef([[flNoPIN]], [[define([[_supportedCVM]], [["NoPIN"]])]])dnl
ifdef([[flOnlinePIN]], [[define([[_supportedCVM]], [["OnlinePIN"]])]])dnl
ifdef([[flLow]], [[define([[_value]], [["Low"]])]])dnl
ifdef([[flHigh]], [[define([[_value]], [["High"]])]])dnl

  choice {
    { "Terminal_Commits_TC":
      [ 'CID cas "TC"
      , 'AIP cas _AIP
      , 'supportedCVM cas _supportedCVM
      , 'transaction cas <'PAN, 'AIP, CVM,
                          <<$amount, country, currency, date, type, ~UN> as PDOL,
                           _CDOL1> as X,
                          ATC, AC, IAD>
      , !Value($amount, _value) ]
    --[ TerminalAccepts('transaction)
      , Commit("Terminal", 'PAN, <"Card", "Terminal", 'transaction>)
      , Honest($CA), Honest($Bank), Honest($Terminal), Honest('PAN)
      ]->
      [
      ]
    };
    { "Terminal_Commits_ARQC":
      [ 'CID cas "ARQC"
      , 'AIP cas _AIP
      , 'supportedCVM cas _supportedCVM
      , 'transaction cas <'PAN, 'AIP, CVM,
                          <<$amount, country, currency, date, type, ~UN> as PDOL,
                           _CDOL1> as X,
                          ATC, AC, IAD>
      , !Value($amount, _value)
      , Recv($Bank, $Terminal, <'channelID, "Mastercard", "2">, <"ARC", ARPC>) ]
    --[ TerminalAccepts('transaction)
      , Commit("Terminal", 'PAN, <"Card", "Terminal", 'transaction>)
      , Commit($Terminal, $Bank, <"Bank", "Terminal", 'transaction>)
      , Honest($CA), Honest($Bank), Honest($Terminal), Honest('PAN)
      ]->
      [
      ]
    }
  }dnl
]]dnl
)

process Terminal_Visa =
  /* Terminal_Sends_GPO_*_Visa */
  choice {
    { "Terminal_Sends_GPO_Low_Visa":
        [ Fr(~UN),
          !Value($amount, "Low") ]
      --
        let date = "YYMMDD" in
        let type = "Purchase" in
        let currency = "CHF" in
        let country = "Switzerland" in
        let TTQ = <"TC", "NoPIN"> in
        let PDOL = <TTQ, $amount, country, currency, date, type, ~UN> in
        [ OneTerminal(),
          Role($Terminal, "Terminal") ]->
        [ Out(<"GET_PROCESSING_OPTIONS", PDOL>),
          'PDOL := PDOL
        ]
    };
    { "Terminal_Sends_GPO_High_Visa":
        [ Fr(~UN),
          !Value($amount, "High") ]
      --
        let date = "YYMMDD" in
        let type = "Purchase" in
        let currency = "CHF" in
        let country = "Switzerland" in
        let TTQ = <"ARQC", "OnlinePIN"> in
        let PDOL = <TTQ, $amount, country, currency, date, type, ~UN> in
        [ OneTerminal(),
          Role($Terminal, "Terminal") ]->
        [ Out(<"GET_PROCESSING_OPTIONS", PDOL>),
          'PDOL := PDOL
        ]
    };
  };

  "Terminal_Sends_ReadRecord_Visa":
    [ In(< AIP, "AFL", <~PAN, expDate>, IAD, AC, CID, ATC, CTQ >),
      'PDOL cas <<acType, CVM>, $amount, country, currency, date, type, ~UN>
    ]
  --[ Compatible_CID_acType(CID, acType) ]->
    [ Out(< "READ_RECORD", "AFL" >),
      'AIP := AIP,
      'PAN := PAN,
      'expDate := expDate,
      'IAD := IAD,
      'AC := AC,
      'CID := CID,
      'ATC := ATC,
      'CTQ := CTQ,
    ];

  /* Terminal_Receives_Records_*_Visa */
  choice {
    { "Terminal_Receives_Records_EMV_Visa":
        [ 'AIP cas <"EMV", _>,
          'CID cas "ARQC",
          In(<'PAN, 'expDate> as records),
          !IssuingBank('PAN, $Bank),
          !CertBank($Bank, <<"02", $Bank, pubkBank, $CA>, sign2>) ]
      -->
        [ 'pubkBank := pubkBank,
          'nc := "Null",
        ]
    };
    { "Terminal_Receives_Records_DDA_Visa":
        [ 'AIP cas <"DDA", _>,
          'PDOL cas <TTQ, $amount, country, currency, date, type, ~UN>,
          In(<'PAN, 'expDate, $CA,
              <<"02", $Bank, pubkBank, $CA>, sign2>,
              <<"04", 'PAN, pubkCard, $Bank>, sign3>,
              nc, CTQ, SDAD>
             as records),
          !IssuingCA($Bank, $CA),
          !SDADFormat(format, 'CID),
          !CertCA($CA, <<"01", $CA, pubkCA, $CA>, sign1>) ]
      --
        ifdef([[flFix]],
        [[let d = <format, nc, 'CID, 'AC, 'PDOL, 'ATC, 'CTQ, ~UN, 'IAD, 'AIP> in]],
        [[let d = <format, 'ATC, ~UN, $amount, "CHF", nc, 'CTQ, 'AIP> in]])
        [ //verify CA's cert (this is possibly not needed)
          Eq( verify(sign1, <"01", $CA, pubkCA, $CA>, pubkCA), true() ),
          //verify the bank's cert
          Eq( verify(sign2, <"02", $Bank, pubkBank, $CA>, pubkCA), true() ),
          //verify the card's cert
          Eq( verify(sign3, <"04", 'PAN, pubkCard, $Bank>, pubkBank), true() ),
          //verify the SDAD
          Eq( verify(SDAD, d, pubkCard), true() )
        ]->
        [ 'pubkBank := pubkBank,
          'nc := nc,
        ]
    };
  };

  /* Terminal_Processes_CVM_*_Visa */
  choice {
    { "Terminal_Processes_CVM_NoPIN_Visa":
        [ 'CTQ cas "NoPIN",
          !Value($amount, "Low") ]
      -->
        [ 'CVM := "NoPIN",
          'encPIN := "Null",
        ]
    };
    { "Terminal_Processes_CVM_CDCVM_Visa":
        [ 'CID cas "ARQC",
          'CTQ cas "CDCVM",
        ]
      -->
        [ 'CVM := "CDCVM",
          'encPIN := "Null",
        ]
    };
    { "Terminal_Processes_CVM_OnlinePIN_Visa":
        [ 'CID cas "ARQC",
          'CTQ cas "OnlinePIN",
          !Entered_PIN('PAN, PIN),//customer or attacker enters PIN
          !Value($amount, "High") ]
      -->
        [ 'CVM := "OnlinePIN",
          'encPIN := aenc(PIN, 'pubkBank),
        ]
    };
  };

  "Terminal_Sends_AC_Visa":
    [ Fr(~channelID) ]
  --
    let transaction = <'PAN, 'AIP, 'CVM, 'PDOL, 'ATC, 'AC, 'IAD> in
    [ Running($Terminal, $Bank, <"Terminal", "Bank", transaction>) ]->
    [ 'channelID := channelID,
      'transaction := transaction,
      Send($Terminal, $Bank, <~channelID, "Visa", "1">, <transaction, 'encPIN>) ]dnl
ifdef([[flVisa]],
[[;
ifdef([[flDDA]], [[define([[_AIP]], [[<"DDA", _furtherData>]])]])dnl
ifdef([[flEMV]], [[define([[_AIP]], [[<"EMV", _furtherData>]])]])dnl
ifdef([[flLow]], [[define([[_value]], [["Low"]])]])dnl
ifdef([[flHigh]], [[define([[_value]], [["High"]])]])dnl

  /* Terminal_Commits_*_Visa */
  choice {
    { "Terminal_Commits_TC_Visa":
        [ 'CID cas "TC",
          'PDOL cas <TTQ, $amount, country, currency, date, type, ~UN>,
          'AIP cas _AIP,
          !Value($amount, _value) ]
      --
        [ TerminalAccepts('transaction),
          Commit("Terminal", 'PAN, <"Card", "Terminal", 'transaction>),
          Honest($CA), Honest($Bank), Honest($Terminal), Honest('PAN) ]->
        [ ]
    };
    { "Terminal_Commits_ARQC_Visa":
        [ 'CID cas "ARQC",
          'PDOL cas <TTQ, $amount, country, currency, date, type, ~UN>,
          'AIP cas _AIP,
          !Value($amount, _value),
          Recv($Bank, $Terminal, <'channelID, "Visa", "2">, <"ARC", ARPC>) ]
      --[ TerminalAccepts('transaction),
          Commit("Terminal", 'PAN, <"Card", "Terminal", 'transaction>),
          Commit($Terminal, $Bank, <"Bank", "Terminal", 'transaction>),
          Honest($CA), Honest($Bank), Honest($Terminal), Honest('PAN)]->
        [ ]
    };
  }
]])

apred BankDeclines/1
pred Bank_Commits/5

process Bank =
  //============== Online Authorization ==============//
  /* Bank_Receives_AC* */
  choice {
    { "Bank_Receives_AC_Failed":
        [ Recv($Terminal, $Bank, <channelID, "Mastercard", "1">,
            <<~PAN, AIP, CVM, X, ATC, AC, IAD> as transaction, encPIN>),
          !Shk(~PAN, ~MK) ]
      --
        let correctAC = MAC(f(~MK, ATC), <X, AIP, ATC, IAD>) in
        [ NEq(correctAC, AC),
          BankDeclines(transaction) ]->
        [ ]
    };
    { "Bank_Receives_AC":
        [ Recv($Terminal, $Bank, <channelID, "Mastercard", "1">,
            <<~PAN, AIP, CVM, X, ATC,
             MAC(f(~MK, ATC), <X, AIP, ATC, IAD>) as AC,
             IAD>
            as transaction,
            encPIN>),
          !Shk(~PAN, ~MK),
          !IssuingBank(~PAN, $Bank) ]
      --
        let ARPC = MAC_arpc(f(~MK, ATC), AC XOR p8("ARC")) in
        [ Once(<~PAN, ATC, "Bank">) ]->
        [ 'transaction := transaction,
          'encPIN := encPIN,
          'channelID := channelID,
          'ARPC := ARPC,
        ];

      /* Bank_Processes_CVM_* */
      choice {
        { "Bank_Processes_CVM_NotOnlinePIN":
            [ 'transaction cas <~PAN, AIP, CVM, X, ATC, AC, IAD>
            , 'encPIN cas "Null" ]
          --[ NEq(CVM, "OnlinePIN"),
              Running($Bank, $Terminal, <"Bank", "Terminal", 'transaction>) ]->
            [
            ]
        };
        { "Bank_Processes_CVM_OnlinePIN":
            [ 'encPIN cas aenc(PIN, pk(~privBank)),
              'transaction cas <~PAN, AIP, "OnlinePIN", X, ATC, AC, IAD>,
              !LtkBank($Bank, ~privkBank),
              !PIN(~PAN, PIN),
              !Shk(~PAN, ~MK) ]
          --[ Running($Bank, $Terminal, <"Bank", "Terminal", 'transaction>) ]->
            [
            ]
        };
      }dnl
ifdef([[flMastercard]],
[[;
ifdef([[flSDA]], [[define([[_AIP]], [[<"SDA", _furtherData>]])]])dnl
ifdef([[flDDA]], [[define([[_AIP]], [[<"DDA", _furtherData>]])]])dnl
ifdef([[flCDA]], [[define([[_AIP]], [[<"CDA", _furtherData>]])]])dnl
ifdef([[flLow]], [[define([[_value]], [["Low"]])]])dnl
ifdef([[flHigh]], [[define([[_value]], [["High"]])]])dnl

      "Bank_Commits":
        [ 'transaction cas <~PAN, _AIP, CVM,
                            <<amount, country, currency, date, type, UN> as PDOL,
                             _CDOL1> as X,
                            _, _, _>
        , !Value(amount, _value)
        , !IssuingCA($Bank, $CA)
        ]
      --[ Commit($Bank, ~PAN, <"Card", "Bank", 'transaction>)
        , Commit($Bank, $Terminal, <"Terminal", "Bank", 'transaction>)
        , Honest($CA), Honest($Bank), Honest($Terminal), Honest(~PAN)
        ]->
        [ Send($Bank, $Terminal, <'channelID, "Mastercard", "2">, <"ARC", 'ARPC>)
        ]
]]
)
    };
  }

pred Bank_Commits_Visa/5

process Bank_Visa =
  /* Bank_Receives_AC*_Visa */
  choice {
    { "Bank_Receives_AC_Failed_Visa":
        [ Recv($Terminal, $Bank, <channelID, "Visa", "1">,
               <<~PAN, AIP, CVM, PDOL, ATC, AC, IAD> as transaction, encPIN>),
          !Shk(~PAN, ~MK) ]
      --
        let correctAC = MAC(f(~MK, ATC), <PDOL, AIP, ATC, IAD>) in
        [ NEq(correctAC, AC),
          BankDeclines(transaction) ]->
        [ ]
    };
    { "Bank_Receives_AC_Visa":
        [ Recv($Terminal, $Bank, <channelID, "Visa", "1">,
            <<~PAN, AIP, CVM, PDOL, ATC, MAC(f(~MK, ATC), <PDOL, AIP, ATC, IAD>) as AC, IAD> as transaction, encPIN>),
          !Shk(~PAN, ~MK),
          !IssuingBank(~PAN, $Bank) ]
      --
        let ARPC = MAC_arpc(f(~MK, ATC), AC XOR p8("ARC")) in
        [ Once(<~PAN, ATC, "Bank">) ]->
        [ 'transaction := transaction,
          'encPIN := encPIN,
          'channelID := channelID,
          'ARPC := ARPC
        ];

      /* Bank_Processes_CVM_*_Visa */
      choice {
        { "Bank_Processes_CVM_NotOnlinePIN_Visa":
            [ 'transaction cas <~PAN, AIP, CVM,
                                <TTQ, amount, country, currency, date, type, UN> as PDOL,
                                ATC, AC, IAD>
            , 'encPIN cas "Null" ]
          --[ NEq(CVM, "OnlinePIN"),
              Running($Bank, $Terminal, <"Bank", "Terminal", 'transaction>) ]->
            [ ]
        };
        { "Bank_Processes_CVM_OnlinePIN_Visa":
            [ 'transaction cas <~PAN, AIP, "OnlinePIN", PDOL, ATC, AC, IAD>,
              'encPIN cas aenc(~PIN, pk(~privkBank)),
              !LtkBank($Bank, ~privkBank),
              !PIN(~PAN, ~PIN) ]
          --[ Running($Bank, $Terminal, <"Bank", "Terminal", 'transaction>) ]->
            [ ]
        };
      }dnl
ifdef([[flVisa]],
[[;
ifdef([[flDDA]], [[define([[_AIP]], [[<"DDA", _furtherData>]])]])dnl
ifdef([[flEMV]], [[define([[_AIP]], [[<"EMV", _furtherData>]])]])dnl
ifdef([[flLow]], [[define([[_value]], [["Low"]])]])dnl
ifdef([[flHigh]], [[define([[_value]], [["High"]])]])dnl

      "Bank_Commits_Visa":
        [ 'transaction cas <~PAN, _AIP as AIP, CVM,
           <TTQ, amount, country, currency, date, type, UN> as PDOL, ATC, AC, IAD>,
          !Value(amount, _value),
          !IssuingCA($Bank, $CA) ]
      --[ Commit($Bank, ~PAN, <"Card", "Bank", 'transaction>),
          Commit($Bank, $Terminal, <"Terminal", "Bank", 'transaction>),
          Honest($CA), Honest($Bank), Honest($Terminal), Honest(~PAN) ]->
        [ Send($Bank, $Terminal, <'channelID, "Visa", "2">, <"ARC", 'ARPC>) ]
]])
    };
  }

restriction equal =
  All a b #i. Eq(a, b)@i ==> a = b

restriction not_equal =
  All a #i. NEq(a, a)@i ==> F

restriction once =
  All a #i #j. Once(a)@i & Once(a)@j ==> #i = #j

restriction unique_role =
  All A r1 r2 #i #j. Role(A, r1)@i & Role(A, r2)@j ==> r1 = r2

restriction compatibility =
  (All #i. Compatible_CID_CVM("TC", "OnlinePIN")@i ==> F) &
  (All #i. Compatible_CID_acType("TC", "ARQC")@i ==> F)

////////////////////////////////////////////
//              Sanity Check              //
////////////////////////////////////////////
lemma executable =
  exists-trace
  Ex Bank PAN t #i #j #k #l.
    i < j &
    Running(PAN, "Terminal", <"Card", "Terminal", t>)@i &
    Commit("Terminal", PAN, <"Card", "Terminal", t>)@j &
    k < l &
    Running(PAN, Bank, <"Card", "Bank", t>)@k &
    Commit(Bank, PAN, <"Card", "Bank", t>)@l &
    (All #a #b. OneCard()@a & OneCard()@b ==> #a = #b) &
    (All #a #b. OneTerminal()@a & OneTerminal()@b ==> #a = #b) &
    (All A B r #a #b. Role(A, r)@a & Role(B, r)@b ==> A = B) &
    not (Ex A #a. Compromise(A)@a)

/////////////////////////////////////////////////////
//           Security Properties                   //
/////////////////////////////////////////////////////
//executable fails for Mastercard High NoPIN, so ignore all following lemmas

undefine([[flproceed]])dnl
ifdef([[flVisa]], [[define([[flproceed]])]])dnl
ifdef([[flLow]], [[define([[flproceed]])]])dnl
ifdef([[flOnlinePIN]], [[define([[flproceed]])]])dnl
ifdef([[flproceed]],
[[
//============== Bank accepts ===========//
lemma bank_accepts =
  All t #i.
    TerminalAccepts(t)@i
   ==>
    not (Ex #j. BankDeclines(t)@j) |
    Ex A #k. Honest(A)@i & Compromise(A)@k

//============== Authentication ===========//
lemma auth_to_terminal_minimal = //non-injective agreement with one card session
  All T' P r t #i.
    (All #a #b. OneCard()@a & OneCard()@b ==> #a = #b) &
    Commit(T', P, <r, "Terminal", t>)@i
   ==>
    (Ex #j. Running(P, T', <r, "Terminal", t>)@j) |
    Ex A #k. Honest(A)@i & Compromise(A)@k

//auth_to_terminal_minimal fails for Visa EMV and for Visa DDA Low
ifdef([[flVisa]],
[[
ifdef([[flDDA]],
[[
undefine([[flproceed]])dnl
ifdef([[flHigh]], [[define([[flproceed]])]])dnl
ifdef([[flFix]], [[define([[flproceed]])]])dnl
ifdef([[flproceed]],
[[
lemma auth_to_terminal = //injective agreement
  All T' P r t #i.
    Commit(T', P, <r, "Terminal", t>)@i
   ==>
    ((Ex #j. Running(P, T', <r, "Terminal", t>)@j & j < i) &
      not (Ex T2 P2 #i2. Commit(T2, P2, <r, "Terminal", t>)@i2 & not(#i2 = #i))
    ) |
    Ex A #k. Honest(A)@i & Compromise(A)@k
]]
)
]]
)
]]
)

//auth_to_terminal_minimal fails for Mastercard SDA Low and for Mastercard DDA Low
ifdef([[flMastercard]],
[[
undefine([[flproceed]])dnl
ifdef([[flHigh]], [[define([[flproceed]])]])dnl
ifdef([[flCDA]], [[define([[flproceed]])]])dnl
ifdef([[flproceed]],
[[
lemma auth_to_terminal = //injective agreement
  All T' P r t #i.
    Commit(T', P, <r, "Terminal", t>)@i
   ==>
    ((Ex #j. Running(P, T', <r, "Terminal", t>)@j & j < i) &
      not (Ex T2 P2 #i2. Commit(T2, P2, <r, "Terminal", t>)@i2 & not(#i2 = #i))
    ) |
    Ex A #k. Honest(A)@i & Compromise(A)@k
]]
)
]]
)

lemma auth_to_bank_minimal = //non-injective agreement with one card session
  All B P r t #i.
    (All #a #b. OneCard()@a & OneCard()@b ==> #a = #b) &
    Commit(B, P, <r, "Bank", t>)@i
   ==>
    (Ex #j. Running(P, B, <r, "Bank", t>)@j) |
    Ex A #k. Honest(A)@i & Compromise(A)@k
//auth_to_bank_minimal fails for Visa EMV
undefine([[flproceed]])dnl
ifdef([[flMastercard]], [[define([[flproceed]])]])dnl
ifdef([[flDDA]], [[define([[flproceed]])]])dnl
ifdef([[flFix]], [[define([[flproceed]])]])dnl
ifdef([[flproceed]],
[[
lemma auth_to_bank = //injective agreement
  All B P r t #i.
    Commit(B, P, <r, "Bank", t>)@i
   ==>
    ((Ex #j. Running(P, B, <r, "Bank", t>)@j & j < i) &
      not (Ex B2 P2 #i2. Commit(B2, P2, <r, "Bank", t>)@i2 & not(#i2 = #i))
    ) |
    Ex A #k. Honest(A)@i & Compromise(A)@k
]]
)
]]
)

//======== Secrecy ======//
lemma secrecy_MK =
  All MK #i.
    SecretMK(MK)@i
   ==>
    not (Ex #j. !KU(MK)@j) | Ex A #k. Honest(A)@i & Compromise(A)@k

undefine([[flproceed]])dnl
ifdef([[flDDA]], [[define([[flproceed]])]])dnl
ifdef([[flCDA]], [[define([[flproceed]])]])dnl
ifdef([[flEMV]], [[define([[flproceed]])]])dnl
ifdef([[flproceed]],
[[
lemma secrecy_privkCard =
  All privkCard #i.
    SecretPrivkCard(privkCard)@i
   ==>
    not (Ex #j. !KU(privkCard)@j) | Ex A #k. Honest(A)@i & Compromise(A)@k
]]
)

undefine([[flproceed]])dnl
ifdef([[flVisa]], [[define([[flproceed]])]])dnl
ifdef([[flOnlinePIN]], [[define([[flproceed]])]])dnl
ifdef([[flproceed]],
[[
lemma secrecy_PIN =
  All PIN #i.
    SecretPIN(PIN)@i
   ==>
    not (Ex #j. !KU(PIN)@j) | Ex A #k. Honest(A)@i & Compromise(A)@k
]]
)

lemma secrecy_PAN =
  All PAN #i.
    SecretPAN(PAN)@i
   ==>
    not (Ex #j. !KU(PAN)@j) | Ex A #k. Honest(A)@i & Compromise(A)@k