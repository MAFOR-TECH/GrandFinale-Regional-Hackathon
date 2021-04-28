pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "../Debot.sol";
import "../Terminal.sol";
import "../Menu.sol";
import "../AddressInput.sol";
import "../ConfirmInput.sol";
import "../Upgradable.sol";
import "../Sdk.sol";

struct Item {
    uint32 id;
    string location;
    uint64 createdAt;
    bool isDone;
}

struct Stat {
    uint32 completeCount;
    uint32 incompleteCount;
}


interface IMsig {
   function sendTransaction(address dest, uint128 value, bool bounce, uint8 flags, TvmCell payload  ) external;
}

abstract contract ASup {
   constructor(uint256 pubkey) public {}
}

interface ISup {
   function createItem(string text) external;
   function updateItem(uint32 id, bool done) external;
   function deleteItem(uint32 id) external;
   function getItems() external returns (Item[] items);
   function getStat() external returns (Stat);
}

contract AgriDebotSupplier is Debot, Upgradable {
    bytes m_icon;

    TvmCell m_supCode; // ITEM contract code
    address m_address;  // ITEM contract address
    Stat m_stat;        // Statistics of incompleted and completed items
    uint32 m_itemId;    // ITEM id for update. I didn't find a way to make this var local
    uint256 m_masterPubKey; // User pubkey
    address m_msigAddress;  // User wallet address

    uint32 INITIAL_BALANCE =  200000000;  // Initial TODO contract balance


    function setSupCode(TvmCell code) public {
        require(msg.pubkey() == tvm.pubkey(), 101);
        tvm.accept();
        m_supCode = code;
    }


       function onError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Operation failed. sdkError {}, exitCode {}", sdkError, exitCode));
        _menu();
    }

    function onSuccess() public view {
        _getStat(tvm.functionId(setStat));
    }

    function start() public override {
        Terminal.input(tvm.functionId(savePublicKey),"Please enter your public key",false);
    }

    
        /// @notice Returns Metadata about DeBot.
    function getDebotInfo() public functionID(0xDEB) override view returns(
        string name, string version, string publisher, string key, string author,
        address support, string hello, string language, string dabi, bytes icon
    ) {
        name = "Agri Supplier DeBot";
        version = "0.1.0";
        publisher = "Agri Drone Tech";
        key = "SUP list manager";
        author = "Drone Tech credits to TON LABS";
        support = address.makeAddrStd(0, 0xa724ee3415cde0ad7ad677ed1eb2b0a5769007de44bbd33be6860d290406d69b);
        hello = "Hi, i'm a AgriDroneTech DeBot.";
        language = "en";
        dabi = m_debotAbi.get();
        icon = m_icon;
    }


        function getRequiredInterfaces() public view override returns (uint256[] interfaces) {
        return [ Terminal.ID, Menu.ID, AddressInput.ID, ConfirmInput.ID ];
    }

    function savePublicKey(string value) public {
        (uint res, bool status) = stoi("0x"+value);
        if (status) {
            m_masterPubKey = res;

            Terminal.print(0, "Checking if you already have a list of Items...");
            TvmCell deployState = tvm.insertPubkey(m_supCode, m_masterPubKey);
            m_address = address.makeAddrStd(0, tvm.hash(deployState));
            Terminal.print(0, format( "Info: your Supplier contract address is {}", m_address));
            Sdk.getAccountType(tvm.functionId(checkStatus), m_address);

        } else {
            Terminal.input(tvm.functionId(savePublicKey),"Wrong public key. Try again!\nPlease enter your public key",false);
        }
    }


    function checkStatus(int8 acc_type) public {
        if (acc_type == 1) { // acc is active and  contract is already deployed
            _getStat(tvm.functionId(setStat));

        } else if (acc_type == -1)  { // acc is inactive
            Terminal.print(0, "You don't have a list of Items yet, so a new contract with an initial balance of 0.2 tokens will be deployed");
            AddressInput.get(tvm.functionId(creditAccount),"Select a wallet for payment. We will ask you to sign two transactions");

        } else  if (acc_type == 0) { // acc is uninitialized
            Terminal.print(0, format(
                "Deploying new contract. If an error occurs, check if your TODO contract has enough tokens on its balance"
            ));
            deploy();

        } else if (acc_type == 2) {  // acc is frozen
            Terminal.print(0, format("Can not continue: account {} is frozen", m_address));
        }
    }


    function creditAccount(address value) public {
        m_msigAddress = value;
        optional(uint256) pubkey = 0;
        TvmCell empty;
        IMsig(m_msigAddress).sendTransaction{
            abiVer: 2,
            extMsg: true,
            sign: true,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(waitBeforeDeploy),
            onErrorId: tvm.functionId(onErrorRepeatCredit)  // Just repeat if something went wrong
        }(m_address, INITIAL_BALANCE, false, 3, empty);
    }


        function onErrorRepeatCredit(uint32 sdkError, uint32 exitCode) public {
        // TODO: check errors if needed.
        sdkError;
        exitCode;
        creditAccount(m_msigAddress);
    }


    function waitBeforeDeploy() public  {
        Sdk.getAccountType(tvm.functionId(checkIfStatusIs0), m_address);
    }

    function checkIfStatusIs0(int8 acc_type) public {
        if (acc_type ==  0) {
            deploy();
        } else {
            waitBeforeDeploy();
        }
    }


function deploy() private view {
            TvmCell image = tvm.insertPubkey(m_supCode, m_masterPubKey);
            optional(uint256) none;
            TvmCell deployMsg = tvm.buildExtMsg({
                abiVer: 2,
                dest: m_address,
                callbackId: tvm.functionId(onSuccess),
                onErrorId:  tvm.functionId(onErrorRepeatDeploy),    // Just repeat if something went wrong
                time: 0,
                expire: 0,
                sign: true,
                pubkey: none,
                stateInit: image,
                call: {ASup, m_masterPubKey}
            });
            tvm.sendrawmsg(deployMsg, 1);
    }


    function onErrorRepeatDeploy(uint32 sdkError, uint32 exitCode) public view {
        // Supplier: check errors if needed.
        sdkError;
        exitCode;
        deploy();
    }

    function setStat(Stat stat) public {
        m_stat = stat;
        _menu();
    }


       function _menu() private {
        string sep = '----------------------------------------';
        Menu.select(
            format(
                "You item has crosed {} (total) Locations",

                    m_stat.completeCount + m_stat.incompleteCount
            ),
            sep,
            [
                //MenuItem("Add new item","",tvm.functionId(createItem)),
                MenuItem("Show item list","",tvm.functionId(showItems)),
                MenuItem("Update item status","",tvm.functionId(updateItem))
                //MenuItem("Delete item","",tvm.functionId(deleteItem))
            ]
        );
    }

    function createItem(uint32 index) public {
        index = index;
        Terminal.input(tvm.functionId(createItem_), "One line please: ProdID: Temp: Location: Time: ", false);
    }

    function createItem_(string value) public view {
        optional(uint256) pubkey = 0;
        ISup(m_address).createItem{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(onSuccess),
                onErrorId: tvm.functionId(onError)
            }(value);
    }

        function showItems(uint32 index) public view {
        index = index;
        optional(uint256) none;
        ISup(m_address).getItems{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: none,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(showItems_),
            onErrorId: 0
        }();
    }


        function showItems_( Item[] items ) public {
        uint32 i;
        if (items.length > 0 ) {
            Terminal.print(0, "Your items list:");
            for (i = 0; i < items.length; i++) {
                Item item = items[i];
                string completed;
                if (item.isDone) {
                    completed = '✓';
                } else {
                    completed = ' ';
                }
                Terminal.print(0, format("{} {}  \"{}\"  at {}", item.id, completed, item.location, item.createdAt));
            }
        } else {
            Terminal.print(0, "Your items list is empty");
        }
        _menu();
    }


    function updateItem(uint32 index) public {
        index = index;
        if (m_stat.completeCount + m_stat.incompleteCount > 0) {
            Terminal.input(tvm.functionId(updateItem_), "Enter item number:", false);
        } else {
            Terminal.print(0, "Sorry, you have no items to update");
            _menu();
        }
    }

    function updateItem_(string value) public {
        (uint256 num,) = stoi(value);
        m_itemId = uint32(num);
        ConfirmInput.get(tvm.functionId(updateItem__),"Is this item completed?");
    }


        function updateItem__(bool value) public view {
        optional(uint256) pubkey = 0;
        ISup(m_address).updateItem{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(onSuccess),
                onErrorId: tvm.functionId(onError)
            }(m_itemId, value);
    }


    function deleteItem(uint32 index) public {
        index = index;
        if (m_stat.completeCount + m_stat.incompleteCount > 0) {
            Terminal.input(tvm.functionId(deleteItem_), "Enter item number:", false);
        } else {
            Terminal.print(0, "Sorry, you have no items to delete");
            _menu();
        }
    }

    function deleteItem_(string value) public view {
        (uint256 num,) = stoi(value);
        optional(uint256) pubkey = 0;
        ISup(m_address).deleteItem{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(onSuccess),
                onErrorId: tvm.functionId(onError)
            }(uint32(num));
    }


    function _getStat(uint32 answerId) private view {
        optional(uint256) none;
        ISup(m_address).getStat{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: none,
            time: uint64(now),
            expire: 0,
            callbackId: answerId,
            onErrorId: 0
        }();
    }

    function onCodeUpgrade() internal override {
        tvm.resetStorage();
    }
}







 