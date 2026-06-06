// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    // Scalar field size
    uint256 constant r = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Base field size
    uint256 constant q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Verification Key data
    uint256 constant alphax = 11985136750761116452303278137378681483621121177462573190829317393722586865774;
    uint256 constant alphay = 14591707249933087796237773015732706425559345124260597617100635684611469486231;
    uint256 constant betax1 = 14958724810706730842427388192145073619628594452258717163041492783535404699187;
    uint256 constant betax2 = 19049982635810346183731411064328298009159059204439904951660975706657899816165;
    uint256 constant betay1 = 12454542857886743693647896710681514455652065753230127566792663043782145816357;
    uint256 constant betay2 = 1143397671874120925493816842337541538457791790957853226133828056492369259115;
    uint256 constant gammax1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant gammax2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant gammay1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 constant gammay2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint256 constant deltax1 = 13942689420835773026297348887863304122308257656880903781249456827273994170535;
    uint256 constant deltax2 = 2611849653816993120572099217330765574194454498774366270295836858653543985312;
    uint256 constant deltay1 = 7545602952201765925665100299472723843629241962400574244564646501987798883232;
    uint256 constant deltay2 = 1211548725025859770263938920401957197305944258714127901466157164259657071565;

    uint256 constant IC0x = 17630259865709898899680833186243049495698929123292931657872214674589902464053;
    uint256 constant IC0y = 4324264233921609125654409365380599535759412993181425974386923807249378560066;

    uint256 constant IC1x = 17564938921365704733891484759298006255944949399347691469071605014879551282249;
    uint256 constant IC1y = 668225537881643776690120332539770036471987386263161690453981398651966726710;

    uint256 constant IC2x = 13485382642242227187065238358440355338274460804046053079853502889600881396118;
    uint256 constant IC2y = 13307362403603782563439905670791774454004453202138475419763196018000046506200;

    uint256 constant IC3x = 16300198485704942096314713879392271362816319325182694878968553221507637107810;
    uint256 constant IC3y = 7919804274995018189701380649179971292547953117333402344773861360651233371541;

    uint256 constant IC4x = 220846965292542391406167499384124934156094992953472885502681173754020048769;
    uint256 constant IC4y = 13566458133827775389933379868286824279959209501373440240011570756039128076665;

    uint256 constant IC5x = 14156261469842671069295323915799621557418070244842825487614923610353185276411;
    uint256 constant IC5y = 7927627332791901513421752528814286975544204266783532252282457072532565228227;

    uint256 constant IC6x = 8813042723495506972164271972108264016277514678713978716985802189138341914808;
    uint256 constant IC6y = 16733692134519667543737120084738189090437733540803965613292439172623976560030;

    uint256 constant IC7x = 4103658211546073034770981029947826715963058222948105635811962152729996495452;
    uint256 constant IC7y = 16977453527407932310092311098995298831486696984450961415154260276673481501798;

    uint256 constant IC8x = 4047960908215358346279314177532308094475337719543592584271592692776878672093;
    uint256 constant IC8y = 3811190960492217794797102902777000716972227105797662229382637670871979991586;

    uint256 constant IC9x = 19932184009440666328648587245691210283775952168392394151553861622589601232506;
    uint256 constant IC9y = 4637264522139388033707811556435579997286955849856934927968120636176578905495;

    uint256 constant IC10x = 4498030366122594720966959611886041109762203548755780592012712694145445061508;
    uint256 constant IC10y = 3829104504911497925483648051315594607825662280649426863892498950469127166982;

    uint256 constant IC11x = 15170624321696755688484694607493929205862524073809389910236580366719970964203;
    uint256 constant IC11y = 21736122110505760166842378216996347804839423305345602206045149870588942091051;

    uint256 constant IC12x = 21141812123789997139979945213816155711999603621861772555380619076953108147580;
    uint256 constant IC12y = 21312342852400348336589451312713652443326814982840474159948688814170021576873;

    uint256 constant IC13x = 4359846189837905314081714388207879572680128192582009091512581085189567617378;
    uint256 constant IC13y = 7500151052538892599204827979240342065634557801162121954471163144996998995638;

    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 896;

    function verifyProof(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[13] calldata _pubSignals
    ) public view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, r)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            // G1 function to multiply a G1 value(x,y) to value in an address
            function g1_mulAccC(pR, x, y, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x)
                mstore(add(mIn, 32), y)
                mstore(add(mIn, 64), s)

                success := staticcall(sub(gas(), 2000), 7, mIn, 96, mIn, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }

                mstore(add(mIn, 64), mload(pR))
                mstore(add(mIn, 96), mload(add(pR, 32)))

                success := staticcall(sub(gas(), 2000), 6, mIn, 128, pR, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                mstore(_pVk, IC0x)
                mstore(add(_pVk, 32), IC0y)

                // Compute the linear combination vk_x

                g1_mulAccC(_pVk, IC1x, IC1y, calldataload(add(pubSignals, 0)))

                g1_mulAccC(_pVk, IC2x, IC2y, calldataload(add(pubSignals, 32)))

                g1_mulAccC(_pVk, IC3x, IC3y, calldataload(add(pubSignals, 64)))

                g1_mulAccC(_pVk, IC4x, IC4y, calldataload(add(pubSignals, 96)))

                g1_mulAccC(_pVk, IC5x, IC5y, calldataload(add(pubSignals, 128)))

                g1_mulAccC(_pVk, IC6x, IC6y, calldataload(add(pubSignals, 160)))

                g1_mulAccC(_pVk, IC7x, IC7y, calldataload(add(pubSignals, 192)))

                g1_mulAccC(_pVk, IC8x, IC8y, calldataload(add(pubSignals, 224)))

                g1_mulAccC(_pVk, IC9x, IC9y, calldataload(add(pubSignals, 256)))

                g1_mulAccC(_pVk, IC10x, IC10y, calldataload(add(pubSignals, 288)))

                g1_mulAccC(_pVk, IC11x, IC11y, calldataload(add(pubSignals, 320)))

                g1_mulAccC(_pVk, IC12x, IC12y, calldataload(add(pubSignals, 352)))

                g1_mulAccC(_pVk, IC13x, IC13y, calldataload(add(pubSignals, 384)))

                // -A
                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), mod(sub(q, calldataload(add(pA, 32))), q))

                // B
                mstore(add(_pPairing, 64), calldataload(pB))
                mstore(add(_pPairing, 96), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))

                // alpha1
                mstore(add(_pPairing, 192), alphax)
                mstore(add(_pPairing, 224), alphay)

                // beta2
                mstore(add(_pPairing, 256), betax1)
                mstore(add(_pPairing, 288), betax2)
                mstore(add(_pPairing, 320), betay1)
                mstore(add(_pPairing, 352), betay2)

                // vk_x
                mstore(add(_pPairing, 384), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 416), mload(add(pMem, add(pVk, 32))))

                // gamma2
                mstore(add(_pPairing, 448), gammax1)
                mstore(add(_pPairing, 480), gammax2)
                mstore(add(_pPairing, 512), gammay1)
                mstore(add(_pPairing, 544), gammay2)

                // C
                mstore(add(_pPairing, 576), calldataload(pC))
                mstore(add(_pPairing, 608), calldataload(add(pC, 32)))

                // delta2
                mstore(add(_pPairing, 640), deltax1)
                mstore(add(_pPairing, 672), deltax2)
                mstore(add(_pPairing, 704), deltay1)
                mstore(add(_pPairing, 736), deltay2)

                let success := staticcall(sub(gas(), 2000), 8, _pPairing, 768, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Validate that all evaluations ∈ F

            checkField(calldataload(add(_pubSignals, 0)))

            checkField(calldataload(add(_pubSignals, 32)))

            checkField(calldataload(add(_pubSignals, 64)))

            checkField(calldataload(add(_pubSignals, 96)))

            checkField(calldataload(add(_pubSignals, 128)))

            checkField(calldataload(add(_pubSignals, 160)))

            checkField(calldataload(add(_pubSignals, 192)))

            checkField(calldataload(add(_pubSignals, 224)))

            checkField(calldataload(add(_pubSignals, 256)))

            checkField(calldataload(add(_pubSignals, 288)))

            checkField(calldataload(add(_pubSignals, 320)))

            checkField(calldataload(add(_pubSignals, 352)))

            checkField(calldataload(add(_pubSignals, 384)))

            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
            return(0, 0x20)
        }
    }
}
