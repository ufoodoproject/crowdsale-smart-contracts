pragma solidity ^0.4.20;


import "./StandardToken.sol";
import "./Ownable.sol";

contract ufoodoToken is StandardToken, Ownable {
    using SafeMath for uint256;

    // Token where will be stored and managed
    address public vault = this;

    string public name = "ufoodo Token";
    string public symbol = "UFT";
    uint8 public decimals = 18;

    // Total Supply DAICO: 500,000,000 UFT
    uint256 public INITIAL_SUPPLY = 500000000 * (10**uint256(decimals));
    // 400,000,000 UFT for DAICO at Q4 2018
    uint256 public supplyDAICO = INITIAL_SUPPLY.mul(80).div(100);

    address public salesAgent;
    mapping (address => bool) public owners;

    event SalesAgentPermissionsTransferred(address indexed previousSalesAgent, address indexed newSalesAgent);
    event SalesAgentRemoved(address indexed currentSalesAgent);

    // 100,000,000 Seed UFT
    function supplySeed() public view returns (uint256) {
        uint256 _supplySeed = INITIAL_SUPPLY.mul(20).div(100);
        return _supplySeed;
    }
    // Constructor
    function ufoodoToken() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(0x0, msg.sender, INITIAL_SUPPLY);
    }
    // Transfer sales agent permissions to another account
    function transferSalesAgentPermissions(address _salesAgent) onlyOwner public {
        emit SalesAgentPermissionsTransferred(salesAgent, _salesAgent);
        salesAgent = _salesAgent;
    }

    // Remove sales agent from token
    function removeSalesAgent() onlyOwner public {
        emit SalesAgentRemoved(salesAgent);
        salesAgent = address(0);
    }

    function transferFromVault(address _from, address _to, uint256 _amount) public {
        require(salesAgent == msg.sender);
        balances[vault] = balances[vault].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Transfer(_from, _to, _amount);
    }

    // Lock the DAICO supply until 2018-09-01 14:00:00
    // Which can then transferred to the created DAICO contract
    function transferDaico(address _to) public onlyOwner returns(bool) {
        require(now >= 1535810400);

        balances[vault] = balances[vault].sub(supplyDAICO);
        balances[_to] = balances[_to].add(supplyDAICO);
        emit Transfer(vault, _to, supplyDAICO);
        return(true);
    }

}
