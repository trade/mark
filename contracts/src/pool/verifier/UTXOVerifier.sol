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

contract UTXOVerifier {
    // Scalar field size
    uint256 constant r =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Base field size
    uint256 constant q =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Verification Key data
    uint256 constant alphax =
        20491192805390485299153009773594534940189261866228447918068658471970481763042;
    uint256 constant alphay =
        9383485363053290200918347156157836566562967994039712273449902621266178545958;
    uint256 constant betax1 =
        4252822878758300859123897981450591353533073413197771768651442665752259397132;
    uint256 constant betax2 =
        6375614351688725206403948262868962793625744043794305715222011528459656738731;
    uint256 constant betay1 =
        21847035105528745403288232691147584728191162732299865338377159692350059136679;
    uint256 constant betay2 =
        10505242626370262277552901082094356697409835680220590971873171140371331206856;
    uint256 constant gammax1 =
        11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant gammax2 =
        10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant gammay1 =
        4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 constant gammay2 =
        8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint256 constant deltax1 =
        8458374183729832463963200503243303095056869648316368100396780612742954678504;
    uint256 constant deltax2 =
        1776033281933226542344272229272822572729454750097703365260356463020801459606;
    uint256 constant deltay1 =
        21495028808161915398014408150267670045510277795460769183806696682919215638179;
    uint256 constant deltay2 =
        15623340882027861969518356994908701618788742285450830768772570068191469778257;

    uint256 constant IC0x =
        8740745857369654401264505518185402133361281239435671471731113783755951515619;
    uint256 constant IC0y =
        6251397655912142856978271804822446110831994834668447327077381451864670746289;

    uint256 constant IC1x =
        13469442830588205682431070781305017546292625485242790872815069778259147029368;
    uint256 constant IC1y =
        3235690339876809288651035682468986790507018631346498813246118295021787074404;

    uint256 constant IC2x =
        12771598389557451583729807681096068133982284519918923899585425808980153718547;
    uint256 constant IC2y =
        1249767514157878238873007302776200600353808605968464111009017310121572758018;

    uint256 constant IC3x =
        10786239293564866132476226370363212091474821670999444870739790524035340977866;
    uint256 constant IC3y =
        7274378934252645687911986503090285322590207131126517614284998255892020747183;

    uint256 constant IC4x =
        1948616737840017067757020836068634596696210849088042847671449512704868162597;
    uint256 constant IC4y =
        5168085688155762594891299846988846878047241674053081832290331939042434185449;

    uint256 constant IC5x =
        2262349298645640887662756525688940526511149963718315618241946689618461926865;
    uint256 constant IC5y =
        4588326634518006329807456365909307684964112407027115399665256012941898553279;

    uint256 constant IC6x =
        21290189624923613875976272145064076286310573550811055163888635885062894273920;
    uint256 constant IC6y =
        3756831822776459523813117860255679331360136576868585289470077554974113762350;

    uint256 constant IC7x =
        8338552650297982363832485178239743262519375472022610887259755858306150581845;
    uint256 constant IC7y =
        21399186970701521001560430787146557857791725245665714307755178287214109715325;

    uint256 constant IC8x =
        12880877837872875545888183574811844214051418829704251860626808059433319029085;
    uint256 constant IC8y =
        856636989885798528318443491927551583888683772352288455923891484597159652278;

    uint256 constant IC9x =
        12866485578152740978434718806011916836060102993248079172087480800474674102214;
    uint256 constant IC9y =
        7063990809820031604696034646858727059831581411089864161216518722042110478094;

    uint256 constant IC10x =
        9829249903066794717120874870430682022159436871666954143368968554903568921500;
    uint256 constant IC10y =
        12734565183155536348226418097717761318942361027746304446595510251400168261016;

    uint256 constant IC11x =
        4656575923749135040717990517506501459550895121401493416805230879258197224914;
    uint256 constant IC11y =
        5018025880660070460934025632982023521306899757661573860538602121409494908808;

    uint256 constant IC12x =
        4719176148154272026493263917947688373278411216369941664772253526610332971831;
    uint256 constant IC12y =
        21431370655651391368357453208020886613390652697414128328309257905741999403335;

    uint256 constant IC13x =
        17415674116954423635916332052729505722329310490913519079895345545410278538429;
    uint256 constant IC13y =
        13536640251312770941188575570403060592839703159851994158436865728896510428848;

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

                g1_mulAccC(
                    _pVk,
                    IC10x,
                    IC10y,
                    calldataload(add(pubSignals, 288))
                )

                g1_mulAccC(
                    _pVk,
                    IC11x,
                    IC11y,
                    calldataload(add(pubSignals, 320))
                )

                g1_mulAccC(
                    _pVk,
                    IC12x,
                    IC12y,
                    calldataload(add(pubSignals, 352))
                )

                g1_mulAccC(
                    _pVk,
                    IC13x,
                    IC13y,
                    calldataload(add(pubSignals, 384))
                )

                // -A
                mstore(_pPairing, calldataload(pA))
                mstore(
                    add(_pPairing, 32),
                    mod(sub(q, calldataload(add(pA, 32))), q)
                )

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

                let success :=
                    staticcall(
                        sub(gas(), 2000),
                        8,
                        _pPairing,
                        768,
                        _pPairing,
                        0x20
                    )

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
