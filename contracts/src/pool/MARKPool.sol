// ... other functions ...

    function withdrawWithSig(
        address creditOwner,
        address recipient,
        uint256 amount,
        bytes32[2] calldata nullifiers,
        uint256 nonce,
        uint256 deadline,
        bytes calldata ownerSignature,
        bytes calldata intentSignature
    ) external nonReentrant whenNotPaused {
        _validateWithdrawRequest(creditOwner, recipient, amount, nonce, deadline, ownerSignature, intentSignature);
        _validateNullifierState(nullifiers);
        _requireWithdrawBindingMatch(nullifiers, creditOwner, recipient, amount);

        (bytes32 intentHash, address intentSigner) = _requireSignatures(
            creditOwner, recipient, amount, nullifiers, nonce, deadline, ownerSignature, intentSignature
        );

        withdrawNonce[creditOwner] = nonce + 1;
        claimedNullifiers[nullifiers[0]] = true;
        claimedNullifiers[nullifiers[1]] = true;
        emit WithdrawIntentAuthorized(intentSigner, intentHash, creditOwner);
        emit NullifierClaimed(nullifiers[0], creditOwner);
        emit NullifierClaimed(nullifiers[1], creditOwner);
        totalNativePaid += amount;

        // Debit RYLA from owner's account FIRST. If this fails, the ETH transfer won't happen.
        ASSET_LEDGER.debit(creditOwner, amount);

        // Transfer ETH to recipient.
        (bool ok, ) = payable(recipient).call{value: amount}("");
        if (!ok) revert NativeTransferFailed();

        emit WithdrawExecuted(creditOwner, recipient, amount, nonce, intentHash, msg.sender);
    }

// ... rest of the contract
