// SPDX-license-identifier: MIT

import {Evvm} from "@EVVM/testnet/contracts/evvm/Evvm.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/strings.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {Treasury} from "@EVVM/testnet/contracts/treasury/Treasury.sol";

pragma solidity ^0.8.29;

contract Trading is Ownable {
    using CAIP10 for string;
    using Strings for string;
    using SafeTransferLib for address;

    struct Credentials {
        address evmDepositorWallet;
        uint256 amount;
    }

    struct SyncUpArguments {
        string caip10Wallet;
        string caip10Token;
        address evmDepositorWallet;
        uint256 newAmount;
    }

    enum ActionIs {
        NATIVE,
        OTHER_CHAIN
    }

    event NewSyncUp(SyncUpArguments[] newInfo);
    event Deposit(
        string caip10Wallet,
        string caip10Token,
        uint256 amount,
        address evmDepositorAddress
    );
    event Withdraw(
        string caip10Wallet,
        string caip10Token,
        uint256 amount,
        address evmDepositorAddress
    );

    error CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE(uint256 have, uint256 want);
    error YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT(address owner);

    address public evvmAddress;
    address public treasuryAddress;

    mapping(string caip10Wallet => mapping(string caip10Token => Credentials credentials))
        public tradeBalance;

    constructor(address _initialOwner, address _evvmAddress, address _treasuryAddress) {
        _initializeOwner(_initialOwner);
        evvmAddress = _evvmAddress;
        treasuryAddress = _treasuryAddress;
    }

    function syncUp(SyncUpArguments[] memory _data) external onlyOwner {
        for (uint256 i = 0; i < _data.length; ) {
            tradeBalance[_data[i].caip10Wallet][
                _data[i].caip10Token
            ] = Credentials({
                evmDepositorWallet: _data[i].evmDepositorWallet,
                amount: _data[i].newAmount
            });
            unchecked {
                i++;
            }
        }
        emit NewSyncUp(_data);
    }

    function deposit(
        string memory _caip10Token,
        string memory _caip10Wallet,
        uint256 _amount,
        ActionIs _action,
        address _depositorWallet
    ) external {
        if (_action == ActionIs.NATIVE) {
            (, string memory tokenAddress) = _caip10Token.parse();
            address token = tokenAddress.parseAddress();
            token.safeTransferFrom(msg.sender, address(this), _amount);
            Treasury(treasuryAddress).deposit(token, _amount);
            tradeBalance[_caip10Wallet][_caip10Token].amount += _amount;
            (, string memory depositorWallet) = _caip10Wallet.parse();
            tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet = depositorWallet.parseAddress();
        } else {
            _checkOwner();
            if (
                tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet ==
                address(0)
            ) {
                tradeBalance[_caip10Wallet][_caip10Token]
                    .evmDepositorWallet = _depositorWallet;
            }
            tradeBalance[_caip10Wallet][_caip10Token].amount += _amount;
        }
        emit Deposit(_caip10Wallet, _caip10Token, _amount, _depositorWallet);
    }

    function withdraw(
        string memory _caip10Token,
        string memory _caip10Wallet,
        uint256 _amount,
        ActionIs _action
    ) external {
        if (_amount > tradeBalance[_caip10Wallet][_caip10Token].amount) {
            revert CANT_WITHDRAW_MORE_THAN_ACCOUNT_HAVE(
                tradeBalance[_caip10Wallet][_caip10Token].amount,
                _amount
            );
        }
        if (tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet != msg.sender) revert YOURE_NOT_THE_OWNER_OF_THE_ACCOUNT(tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet);
        if (_action == ActionIs.NATIVE) {
            (, string memory tokenAddress) = _caip10Token.parse();
            address token = tokenAddress.parseAddress();
            Treasury(treasuryAddress).withdraw(token, _amount);
            token.safeTransfer(msg.sender, _amount);
            tradeBalance[_caip10Wallet][_caip10Token].amount -= _amount;
        } else {
            _checkOwner();
            tradeBalance[_caip10Wallet][_caip10Token].amount -= _amount;
        }
        emit Withdraw(_caip10Wallet, _caip10Token, _amount, tradeBalance[_caip10Wallet][_caip10Token].evmDepositorWallet);
    }
}
