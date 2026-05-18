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

pragma solidity ^0.8.25;

contract MARKPoolVerifier {
    // Scalar field size
    uint256 constant r = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Base field size
    uint256 constant q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Verification Key data
    uint256 constant alphax = 7690121453837064741791666285615914065043168911112024434635727450696948422155;
    uint256 constant alphay = 19345384908200007096220441272874255011681315248075750381704111138335765955939;
    uint256 constant betax1 = 6915934800673380020968239961322121395269172970533534101674332671678415647246;
    uint256 constant betax2 = 20728849236918147024992766736188414469847245385633192207887668658686399927588;
    uint256 constant betay1 = 21312787228846701455550273385994038986810827549346222493309345736711813078377;
    uint256 constant betay2 = 16286369113203485455529573339382241219652132627904969020690079721408278626154;
    uint256 constant gammax1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant gammax2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant gammay1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 constant gammay2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint256 constant deltax1 = 18345997162799119763959895099884005794908640345221290015934691352832684803409;
    uint256 constant deltax2 = 18376220675637683916789943756353088518300600925197561931224366358883175144946;
    uint256 constant deltay1 = 14667787894595027688399092139120199969307647556867024352155398167389948755220;
    uint256 constant deltay2 = 17402953593761902101339812066866095628747519305463643507602187887465365773563;

    uint256 constant IC0x = 19677464199829831391143197766895170870202127014521187688146355322194167148789;
    uint256 constant IC0y = 14508738950164930345796428833546353070862474607782487610541850087929116474823;

    uint256 constant IC1x = 15810506242982102758328405285766847137006576574868460171387725247110566628643;
    uint256 constant IC1y = 11938198121287064712385776490568305466880644396271008528046426042839610914074;

    uint256 constant IC2x = 18060475454236239168879174600455192598240591544351300374321852531007429009260;
    uint256 constant IC2y = 10296541415987206312466055552238695162994563741943336332647294514514935225702;

    uint256 constant IC3x = 3990251842151791550142883039865846292187659831760645494713083817305989709105;
    uint256 constant IC3y = 1304028740140725426252032502949428173892032776255032882042899910509473360120;

    uint256 constant IC4x = 21395198740199805844451312446272709617147392380661710468534185462130281275251;
    uint256 constant IC4y = 12578747072742829252091273986932145672426413050540548117821316259630037256762;

    uint256 constant IC5x = 14655361099279462571711764477264712958209045342810426112622760020406723477975;
    uint256 constant IC5y = 16473077741198686033561698162265512156626032674621230865444064605841618114186;

    uint256 constant IC6x = 8339902252239795081910729652265595713879123333853824977475238292919724589513;
    uint256 constant IC6y = 9820528359329116982730541353201661834578929514941329926803536170951379309866;

    uint256 constant IC7x = 9617676558640460423141383812130917145761139647874321775264012149719154634990;
    uint256 constant IC7y = 19593893247410006121291214540215535963752641361334134681489375464166464502639;

    uint256 constant IC8x = 10096618593207197176611766393169319752761689442500959997102862948250829793082;
    uint256 constant IC8y = 17494166304952791491504140178523726688997463801000163628380743050969222835058;

    uint256 constant IC9x = 13229071062576027181470319239919008050027368487464842689099423968901005572714;
    uint256 constant IC9y = 14079217861664032079295362303322009278793429507935279509898657532006155661451;

    uint256 constant IC10x = 9870923827008178781317591932446971439112779463121740091254410422921350400337;
    uint256 constant IC10y = 1219780025409560941514831026892781911586565452764231309711241768110330035679;

    uint256 constant IC11x = 18018388542095146381096718473114112195585557454998366946299555005537522886657;
    uint256 constant IC11y = 9755299296218437764934573811016436707100541752064000523732170157502071982459;

    uint256 constant IC12x = 10763815019232165310646098723787191585893365403641063356783612748255221441294;
    uint256 constant IC12y = 20630753604272640342314204407594751978163768046423435894514917305447912351616;

    uint256 constant IC13x = 15573237768046962222146529676543444045309562040107000847925173039157817674084;
    uint256 constant IC13y = 16229429557329522323758870379600272246081875321482243209760555251354229611954;

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
