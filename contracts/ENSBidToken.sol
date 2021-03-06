pragma solidity ^0.4.11;

import "./token/StandardToken.sol";
import "./ownership/Ownable.sol";

contract ENSBidToken is StandardToken, Ownable {
  // [x] 實作 ERC20 
  // [x] 股權形式分配的 Token 模式
  // [x] 開發團隊的 Token 鎖定一年
  // [x] 發售 50%，開發團隊 50%
  // [x] 分潤模式，提供一個 function 可以將分配利潤發放給 token holder

  event ShareBenefit(string _tx, address _shareHolder, uint256 _balance, uint256 _shareBenefit);
  event BenefitReportInfo(uint _year, uint _month, uint256 _benefitInWei);
  event Finalized();

  string public name;                                   // 名稱
  string public symbol;                                 // token 代號
  uint256 public decimals = 0;                          // decimals
  address public contractAddress;                       // contract address
  address public ownerWalletAddress;                    // owner wallet address
  uint256 public minInvestInWei;                        // 最低投資金額 in wei
  uint256 public startBlock;                            // ICO 起始的 block number
  uint256 public endBlock;                              // ICO 結束的 block number
  uint256 public maxTokenSupply;                        // ICO 的 max token，透過 USD to ETH 換算出來
  uint256 public initializedTime;                       // 起始時間，合約部署的時候會寫入
  uint256 public lockoutTime;                           // develop team lock time 

  bool public paused;                                   // 暫停合約功能執行
  bool public initialized;                              // 合約啟動
  uint256 public finalizedBlock;                        // 合約終止投資的區塊編號
  uint256 public finalizedTime;                         // 合約終止投資的時間

  struct ShareHolder {
    bool isExists;
    bool isPayable;
    uint256 shareBenefitInWei;  
  }

  struct BenefitReport {
    uint year;
    uint month;
    uint256 benefitInWei;
  }

  ShareHolder public shareHolder;
  BenefitReport public benefitReport;

  mapping (address => ShareHolder) public shareHolders; 
  address[] public shareHolderArray;                    // share holder array
  BenefitReport[] public benefitReportArray;
  
  /**
   * @dev Throws if contract paused.
   */
  modifier notPaused() {
    require(paused == false);
    _;
  }

  /**
   * @dev Throws if contract is paused.
   */
  modifier isPaused() {
    require(paused == true);
    _;
  }

  /**
   * @dev Throws if contract not initialized. 
   */
  modifier isInitialized() {
    require(initialized == true);
    _;
  }

  /**
   * @dev Throws if owner token in lockout period.  
   */
  modifier notLockout() {
    require(msg.sender != ownerWalletAddress || now > (finalizedTime + lockoutTime));
    _;
  }

  /**
   * @dev Throws if contract not open. 
   */
  modifier isContractOpen() {
    require(
      getBlockNumber() >= startBlock &&
      getBlockNumber() <= endBlock &&
      finalizedBlock == 0);
    _;
  }

  modifier isFinalized() {
    require(finalizedBlock > 0 && 
      finalizedTime > 0);
    _;
  }

  /**
   * @dev Contract constructor.
   */
  function ENSBidToken() {
    paused = false;
  }

  function initialize(
      string _name,
      string _symbol,
      uint256 _decimals,
      address _contractAddress,
      address _ownerWalletAddress,
      uint256 _startBlock,
      uint256 _endBlock,
      uint256 _initializedTime,
      uint256 _lockoutTime,
      uint256 _minInvestInWei,
      uint256 _maxTokenSupply) onlyOwner {
    require(bytes(name).length == 0);
    require(bytes(symbol).length == 0);
    require(decimals == 0);
    require(contractAddress == 0x0);
    require(ownerWalletAddress == 0x0);
    require(totalSupply == 0);
    require(decimals == 0);
    require(_startBlock >= getBlockNumber());
    require(_startBlock < _endBlock);
    require(initializedTime == 0);
    require(lockoutTime == 0);
    require(_maxTokenSupply >= totalSupply);
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    contractAddress = _contractAddress;
    ownerWalletAddress = _ownerWalletAddress;
    startBlock = _startBlock;
    endBlock = _endBlock;
    initializedTime = _initializedTime;
    lockoutTime = _lockoutTime;
    minInvestInWei = _minInvestInWei;
    maxTokenSupply = _maxTokenSupply;
    initialized = true;
  }

  /**
   * @dev Finalize contract
   */
  function finalize() public isInitialized {
    require(getBlockNumber() >= startBlock);
    require(msg.sender == owner || getBlockNumber() > endBlock);

    finalizedBlock = getBlockNumber();
    finalizedTime = now;

    Finalized();
  }

  /**
   * @dev fallback function accept ether
   */
  function () payable {
    proxyPayment(msg.sender);
  }

  /**
   * @dev payment function, transfer eth to token
   * @param _sender The sender address
   */
  function proxyPayment(address _sender) public payable notPaused isInitialized isContractOpen returns (bool) {
    require(msg.value > 0);

    uint256 amount = msg.value;
    require(amount >= minInvestInWei); 

    uint256 refund = amount % minInvestInWei;                     // 退款機制
    uint256 tokens = (amount - refund) / minInvestInWei;          // 透過最小投注金額換算所得的token數量  
    uint256 totalTokens = tokens * 2;
    require(totalSupply.add(totalTokens) <= maxTokenSupply);
    totalSupply = totalSupply.add(totalTokens);
    balances[_sender] = balances[_sender].add(tokens);            // 發送 token 給投資者
    balances[owner] = balances[owner].add(tokens);                // 發送 token 給開發者

    if (shareHolders[msg.sender].isExists != true) {
      shareHolders[msg.sender].isExists = true;
      shareHolders[msg.sender].isPayable = true;
      shareHolderArray.push(msg.sender);
    }

    require(ownerWalletAddress.send(amount - refund));                         // 扣掉退款金額，將ETH轉到owner錢包中
    if (refund > 0) {
      require(msg.sender.send(refund));                           // 傳送退款金額給 msg.sender
    }
    return true;
  }

  /**
   * @dev pause contract
   */
  function pauseContract() onlyOwner {
    paused = true;
  }

  /**
   * @dev resume contract
   */
  function resumeContract() onlyOwner {
    paused = false;
  }

  /**
   * @dev get block number
   */
  function getBlockNumber() internal constant returns (uint256) {
    return block.number;
  }

  /**
   * @dev Aprove the passed address to spend the specified amount of tokens on behalf of msg.sender.
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
  function approve(address _spender, uint256 _value) notLockout returns (bool) {
    require((_value == 0) || (allowed[msg.sender][_spender] == 0));
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifing the amount of tokens still avaible for the spender.
   */
  function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }

  /**
   * @dev ERC20 transfer
   */
  function transfer(address _to, uint256 _value) notPaused isFinalized notLockout returns (bool) {
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    if (shareHolders[_to].isExists != true) {
      shareHolders[_to].isExists = true;
      shareHolders[_to].isPayable = true;
      shareHolderArray.push(_to);
    }
    Transfer(msg.sender, _to, _value);
    return true;
  }

  /**
   * @dev ERC20 transferFrom
   */
  function transferFrom(address _from, address _to, uint256 _value) notPaused isFinalized returns (bool) {
    var _allowance = allowed[_from][msg.sender];
    balances[_to] = balances[_to].add(_value);
    balances[_from] = balances[_from].sub(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    if (shareHolders[_to].isExists != true) {
      shareHolders[_to].isExists = true;
      shareHolders[_to].isPayable = true;
      shareHolderArray.push(_to);
    }
    Transfer(_from, _to, _value);
    return true;
  }

  /**
   * gas per address: 5560
   * @dev share in the benefit
   * @param _address address of token holders
   * @param _benefitInWei benefit in wei to token holders
   */
  function shareBenefit(address[] _address, uint256[] _benefitInWei) onlyOwner {
    require(_address.length > 0);
    require(_address.length == _benefitInWei.length);
    uint256 i = 0;
    while (i < _address.length && msg.gas > 3000000) {
      address _shareHolder = _address[i];
      shareHolders[_shareHolder].shareBenefitInWei += _benefitInWei[i];
      i++;
    }
  }

  /**
   * @dev owner deposit benefit ETH and store in BenefitReport
   * @param _year year of benefit report
   * @param _month month of benefit report
   */
  function depositBenefit(uint _year, uint _month) onlyOwner payable {
    require(msg.value > 0);
    benefitReportArray.push(BenefitReport(_year, _month, msg.value));
    BenefitReportInfo(_year, _month, msg.value);
  }
}
