// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Token.sol";
import "./BondingCurve.sol";
import "@openzeppelin-contracts-5.0.2/access/Ownable.sol";
import "@openzeppelin-contracts-5.0.2/utils/Pausable.sol";
import "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";
import "@uniswap-v3-periphery-1.4.4/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap-v3-periphery-1.4.4/contracts/interfaces/ISwapRouter.sol";
import "@uniswap-v3-core-1.0.2-solc-0.8-simulate/contracts/interfaces/IUniswapV3Factory.sol";

struct TokenInfo {
    string name;
    string symbol;
    string uri;
    bool launched;
}

contract MintMania is Ownable, Pausable {
    uint256 public constant MAX_SUPPLY = 1000_000_000; // 1 billion
    uint256 public constant INITIAL_SUPPLY = 200_000_000; // 20 million (20% of max supply)
    uint256 public constant INITAL_PRICE = 1;
    uint256 public constant INITIAL_COLLATORAL = 1000_000_000; // 1k usdt
    uint32 private constant RR = 350000; // part per milliom
    address private constant UNISWAP_V3_FACTORY_ADDRESS =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant NONFUNGIBLE_POSITION_MANAGER_ADDRESS =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    IUniswapV3Factory private uniswapV3Factory;
    INonfungiblePositionManager private nonfungiblePositionManager;

    IERC20 public immutable stableToken;
    BancorBondingCurve public immutable bondingCurve;

    mapping(address => TokenInfo) private tokens;
    mapping(address => mapping(address => uint256)) private balances;
    mapping(address => uint256) private tokenEthBalance;
    mapping(address => uint256) private usdtSuplly;

    constructor(address owner, address _usdt) Ownable(owner) {
        stableToken = IERC20(_usdt);
        bondingCurve = new BancorBondingCurve();
        uniswapV3Factory = IUniswapV3Factory(UNISWAP_V3_FACTORY_ADDRESS);
        nonfungiblePositionManager = INonfungiblePositionManager(
            NONFUNGIBLE_POSITION_MANAGER_ADDRESS
        );
    }

    event TokenCreated(address token, string name, string symbol);
    event TokenBought(
        address token,
        address buyer,
        uint256 amount,
        uint256 price
    );
    event TokenSold(
        address token,
        address seller,
        uint256 amount,
        uint256 price
    );

    function create(
        string memory name,
        string memory symbol,
        string memory uri
    ) external whenNotPaused {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(bytes(uri).length > 0, "URI cannot be empty");

        Token token = new Token(name, symbol, INITIAL_SUPPLY, MAX_SUPPLY);
        tokens[address(token)] = TokenInfo(name, symbol, uri, false);
        usdtSuplly[address(token)] = INITIAL_COLLATORAL;
        emit TokenCreated(address(token), name, symbol);
    }

    // amount in token
    function buy(address token, uint256 amount) external payable whenNotPaused {
        require(bytes(tokens[token].name).length > 0, "Token does not exist");
        require(amount > 0, "Amount must be greater than 0");

        uint256 _supply = Token(token).totalSupply();
        uint256 amountToken = bondingCurve.calculatePurchaseReturn(
            _supply,
            usdtSuplly[token],
            RR,
            amount
        );

        // withdraw from usdt contract
        require(
            stableToken.balanceOf(msg.sender) >= amount,
            "Insufficient balance"
        );
        require(
            stableToken.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );
        require(
            stableToken.transferFrom(msg.sender, address(this), amount) == true,
            "Transfer failed"
        );

        require(Token(token).mint(msg.sender, amountToken) == true);
        usdtSuplly[token] += amount;

        emit TokenBought(token, msg.sender, amount, getPrice(token));
    }

    function sell(address token, uint256 amountToken) external whenNotPaused {
        require(bytes(tokens[token].name).length > 0, "Token does not exist");
        require(amountToken > 0, "Amount must be greater than 0");

        uint256 _supply = Token(token).totalSupply();
        uint256 amount = bondingCurve.calculateSaleReturn(
            _supply,
            usdtSuplly[token],
            RR,
            amountToken
        );

        require(Token(token).burn(msg.sender, amountToken) == true);
        usdtSuplly[token] -= amount;

        emit TokenSold(token, msg.sender, amount, getPrice(token));
    }

    function calculateTokenReturn(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        require(bytes(tokens[token].name).length > 0, "Token does not exist");
        require(amount > 0, "Amount must be greater than 0");
        uint256 _supply = Token(token).totalSupply();

        return
            bondingCurve.calculatePurchaseReturn(
                _supply,
                usdtSuplly[token],
                RR,
                amount
            );
    }

    function getPrice(address token) public view returns (uint256) {
        require(bytes(tokens[token].name).length > 0, "Token does not exist");

        uint256 _supply = Token(token).totalSupply();

        return
            bondingCurve.calculateSaleReturn(_supply, usdtSuplly[token], RR, 1);
    }

    function getMarketCap(address token) external view returns (uint256) {
        require(bytes(tokens[token].name).length > 0, "Token does not exist");
        return usdtSuplly[token];
    }

    function launch(address token) external onlyOwner {
        require(bytes(tokens[token].name).length > 0, "Token does not exist");
        require(tokens[token].launched == false, "Token is already launched");

        // integrate dex

        tokens[token].launched = true;
    }

    function addLiquidity(address token) private {
        Token(token).approve(
            address(nonfungiblePositionManager),
            INITIAL_SUPPLY
        );
        stableToken.approve(address(nonfungiblePositionManager), usdtAmount);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: DAI,
                token1: USDC,
                fee: poolFee,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
