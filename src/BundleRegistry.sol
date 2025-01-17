// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

import {IdRegistry} from "./IdRegistry.sol";
import {NameRegistry} from "./NameRegistry.sol";

/**
 * @title BundleRegistry
 * @author varunsrin (@v)
 * @custom:version 2.0.0
 *
 * @notice BundleRegistry allows user to register a Farcaster Name and Farcaster ID in a single
 *         transaction by wrapping around the IdRegistry and NameRegistry contracts, saving gas and
 *         reducing complexity for the caller.
 */
contract BundleRegistry is Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when the caller does not have the authority to perform the action
    error Unauthorized();

    /// @dev Revert when excess funds could not be sent back to the caller
    error CallFailed();

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emit when the trustedCaller is changed by the owner after the contract is deployed
    event ChangeTrustedCaller(address indexed trustedCaller, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The data required to trustedBatchRegister a single user
    struct BatchUser {
        address to;
        bytes16 username;
    }

    /// @dev The only address that can call trustedRegister and partialTrustedRegister
    address internal trustedCaller;

    /// @dev The address of the IdRegistry contract
    IdRegistry internal immutable idRegistry;

    /// @dev The address of the NameRegistry UUPS Proxy contract
    NameRegistry internal immutable nameRegistry;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the addresses of the Registry contracts and the trusted caller which is
     *        allowed to register during the bootstrap phase.
     *
     * @param _idRegistry The address of the IdRegistry contract
     * @param _nameRegistry The address of the NameRegistry UUPS Proxy contract
     * @param _trustedCaller The address that can call trustedRegister and partialTrustedRegister
     */
    constructor(address _idRegistry, address _nameRegistry, address _trustedCaller) Ownable() {
        idRegistry = IdRegistry(_idRegistry);
        nameRegistry = NameRegistry(_nameRegistry);
        trustedCaller = _trustedCaller;
    }

    /**
     * @notice Register an fid and an fname during the final Mainnet phase, where registration is
     *         open to everyone.
     */
    function register(address to, address recovery, bytes16 username, bytes32 secret) external payable {
        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.register(to, recovery);
        // Audit: is it possible to drain funds that you did not send in here?
        nameRegistry.register{value: msg.value}(username, to, secret, recovery);

        // Return any funds returned by the NameRegistry back to the caller
        if (address(this).balance > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = msg.sender.call{value: address(this).balance}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Register an fid and an fname during the first Mainnet phase, where registration of
     *         the fid is available to all, but registration of the fname can only be performed by
     *         the Farcaster Bootstrap Server (trustedCaller)
     */
    function partialTrustedRegister(address to, address recovery, bytes16 username) external payable {
        // Do not allow anyone except the Farcaster Bootstrap Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.register(to, recovery);
        nameRegistry.trustedRegister(username, to, recovery);
    }

    /**
     * @notice Register an fid and an fname during the Goerli phase, where registration can only be
     *         performed by the Farcaster Bootstrap Server (trustedCaller)
     */
    function trustedRegister(address to, address recovery, bytes16 username) external payable {
        // Do not allow anyone except the Farcaster Bootstrap Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.trustedRegister(to, recovery);
        nameRegistry.trustedRegister(username, to, recovery);
    }

    /**
     * @notice Register multiple fids and fname during a migration to a new network, where
     *         registration can only be performed by the Farcaster Bootstrap Server (trustedCaller).
     *         Recovery address is initialized to default value during this migration.
     */
    function trustedBatchRegister(BatchUser[] calldata users) external {
        // Do not allow anyone except the Farcaster Bootstrap Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        for (uint256 i = 0; i < users.length; i++) {
            idRegistry.trustedRegister(users[i].to, address(0));
            nameRegistry.trustedRegister(users[i].username, users[i].to, address(0));
        }
    }

    /**
     * @notice Change the trusted caller that can call trustedRegister and partialTrustedRegister
     */
    function changeTrustedCaller(address _trustedCaller) external onlyOwner {
        if (_trustedCaller == address(0)) revert InvalidAddress();

        trustedCaller = _trustedCaller;
        emit ChangeTrustedCaller(_trustedCaller, msg.sender);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
