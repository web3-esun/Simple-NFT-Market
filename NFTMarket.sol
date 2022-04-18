// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract NFTItem1155 is ERC1155,AccessControl {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    mapping (uint256 => string) private _uris;
    // address  private _creater;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory first_metadataURL,address creater)  ERC1155("") {
        _mint(creater,_tokenIds.current(),1,"");
        _uris[_tokenIds.current()] = first_metadataURL;
        // _creater = creater;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, creater);
        _tokenIds.increment();
    }
    

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to Owner.");
        _;
    } 

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override (AccessControl, ERC1155) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function uri(uint256 tokenId) override public view returns (string memory) {
        return(_uris[tokenId]);
    }
    
    function setTokenUri(uint256 tokenId, string memory _uri) public onlyOwner {
        require(bytes(_uris[tokenId]).length == 0, "Cannot set uri twice"); 
        _uris[tokenId] = _uri; 
    }

    function mint(address creater,string memory metadataURL) public onlyOwner returns (uint){
        // require(_creater==creater,"Not first creater");
        require(hasRole(MINTER_ROLE, creater), "must have minter role to mint");
        uint256 newTokenId = _tokenIds.current();
        _mint(creater,newTokenId,1,"");
        _uris[newTokenId] = metadataURL;
        _tokenIds.increment();

        return newTokenId;
    }

    function TransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public onlyOwner{
        _safeTransferFrom(from,to,id,amount,data);
    }

}





contract BigantMarket is AccessControl {

    mapping(address => mapping(uint256=>sellItem)) public selling;
    mapping(address => mapping(uint256=>auctionItem)) public auction;

    address[] public contractSelling;

    mapping(address => uint256) public balances;
    struct sellItem{
        uint256 price;
        address owner;
        bool isSelling;
    }

    struct auctionItem{
        address owner;
        uint256 highestBid;
        address highestBidder;
        uint256 auctionEndTime;
        bool isEnd;
    }

    constructor() {
         _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to Owner.");
        _;
    } 

    event HighestBidIncreased(address bidder, uint amount);
    event AuctionEnded(address winner, uint amount);

    function getNowSelling() public view  returns( address  [] memory){
        return contractSelling;
    }

    function createFirstItemforsell(uint256 price,string memory metadataUrl) public {
        address contractAddr =address(new NFTItem1155(metadataUrl,msg.sender));
        selling[contractAddr][0] = sellItem(price,msg.sender,true);
        contractSelling.push(contractAddr);
    }

    function addNewItemforsell(address contractAddr,uint256 price,string memory metadataUrl) public returns (uint256)
    {
        
        NFTItem1155 token = NFTItem1155(contractAddr);
        // require(token.isApprovedForAll(msg.sender,address(this)),"contract must be approve");
        uint256 tokenId = token.mint(msg.sender,metadataUrl);
        selling[contractAddr][tokenId] = sellItem(price,msg.sender,true);
        return tokenId;
    }

    function createFirstItemforsell_bid(uint256 price,uint256 biddingTime,string memory metadataUrl) public {
        address contractAddr =address(new NFTItem1155(metadataUrl,msg.sender));
        auction[contractAddr][0] = auctionItem(msg.sender,price,msg.sender,block.timestamp + biddingTime,false);
        contractSelling.push(contractAddr);
    }

    // function addNewItemforsell(address contractAddr,uint256 price,string memory metadataUrl) public returns (uint256)
    // {
        
    //     NFTItem1155 token = NFTItem1155(contractAddr);
    //     // require(token.isApprovedForAll(msg.sender,address(this)),"contract must be approve");
    //     uint256 tokenId = token.mint(msg.sender,metadataUrl);
    //     selling[contractAddr][tokenId] = sellItem(price,msg.sender,true);
    //     return tokenId;
    // }



    function purchase(address contractAddr, uint256 tokenId) public payable{
        sellItem memory item = selling[contractAddr][tokenId];
        require(msg.value >= item.price, "Not enough");
        require(item.isSelling == true,"Not for sell");

        NFTItem1155 token = NFTItem1155(contractAddr);
        token.TransferFrom(item.owner,msg.sender,tokenId,1,"");

        selling[contractAddr][tokenId].isSelling = false;

        balances[item.owner] += msg.value;

        selling[contractAddr][tokenId].owner = msg.sender;
    }

    function withdraw(uint256 amount) public {
        require(amount <= balances[msg.sender]," not enough ");

        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
    
    function bid(address NFTAddr,uint256 tokenId) public payable {
        require(
            block.timestamp <= auction[NFTAddr][tokenId].auctionEndTime,
            "Auction already ended."
        );
        require(!auction[NFTAddr][tokenId].isEnd, "Auction already ended Flag");
        require(
            msg.value > auction[NFTAddr][tokenId].highestBid,
            "There already is a higher bid."
        );

        if (auction[NFTAddr][tokenId].owner != auction[NFTAddr][tokenId].highestBidder) {
            balances[auction[NFTAddr][tokenId].highestBidder] += auction[NFTAddr][tokenId].highestBid;
        }
        auction[NFTAddr][tokenId].highestBid = msg.value;
        auction[NFTAddr][tokenId].highestBidder = msg.sender;
        emit HighestBidIncreased(msg.sender, msg.value);
    }

    function auctionEnd(address NFTAddr,uint256 tokenId) public onlyOwner{
        require(block.timestamp >= auction[NFTAddr][tokenId].auctionEndTime, "Auction not yet ended.");
        require(!auction[NFTAddr][tokenId].isEnd, "auctionEnd has already been called.");

        auction[NFTAddr][tokenId].isEnd = true;
        emit AuctionEnded(auction[NFTAddr][tokenId].highestBidder, auction[NFTAddr][tokenId].highestBid);

        NFTItem1155 token = NFTItem1155(NFTAddr);
        token.TransferFrom(auction[NFTAddr][tokenId].owner,auction[NFTAddr][tokenId].highestBidder,tokenId,1,"");
        balances[auction[NFTAddr][tokenId].owner] += auction[NFTAddr][tokenId].highestBid;
    }

}
