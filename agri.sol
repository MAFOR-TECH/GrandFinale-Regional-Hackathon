 pragma ton-solidity >= 0.35.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

contract AgriSupplier {
    /*
     * ERROR CODES
     * 100 - Unauthorized
     * 102 - items not found
     */

    modifier onlyOwner() {
        require(msg.pubkey() == m_ownerPubkey, 101);
        _;
    }

    uint32 m_count;

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

    mapping(uint32 => Item) m_items;

    uint256 m_ownerPubkey;

        constructor( uint256 pubkey) public {
        require(pubkey != 0, 120);
        tvm.accept();
        m_ownerPubkey = pubkey;
    }

        function createItem(string location) public onlyOwner {
        tvm.accept();
        m_count++;
        m_items[m_count] = Item(m_count, location, now, false);
    }

    function updateItem(uint32 id, bool done) public onlyOwner {
        optional(Item) item = m_items.fetch(id);
        require(item.hasValue(), 102);
        tvm.accept();
        Item thisItem = item.get();
        thisItem.isDone = done;
        m_items[id] = thisItem;
    }

    function deleteItem(uint32 id) public onlyOwner {
        require(m_items.exists(id), 102);
        tvm.accept();
        delete m_items[id];
    }

    //
    // Get methods
    //

        function getItems() public view returns (Item[] items) {
        string location;
        uint64 createdAt;
        bool isDone;

        for((uint32 id, Item item) : m_items) {
            location = item.location;
            isDone = item.isDone;
            createdAt = item.createdAt;
            items.push(Item(id, location, createdAt, isDone));
       }
    }


       function getStat() public view returns (Stat stat) {
        uint32 completeCount;
        uint32 incompleteCount;

        for((, Item item) : m_items) {
            if  (item.isDone) {
                completeCount ++;
            } else {
                incompleteCount ++;
            }
        }
        stat = Stat( completeCount, incompleteCount );
    }
}