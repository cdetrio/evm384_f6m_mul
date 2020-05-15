{
    function memcpy_384(dst, src) {
        let hi := mload(src)
        let lo := mload(add(src, 32))
        mstore(dst, hi)
        mstore(add(dst, 32), lo)
    }

    function mulNR2(x0, x1, r0, r1, modulus, arena) {
        let x0c := arena
        memcpy_384(x0c, x0) // copy x0 to x0c
        // r0 <- x0 - x1
        submod384(r0, x0, x1, modulus)
        // r1 <- x0 + x1
        addmod384(r1, x0c, x1, modulus)
    }

    // r <- x + y
    function f2m_add(x_0, x_1, y_0, y_1, r_0, r_1, modulus, arena) {
        addmod384(r_0, x_0, y_0, modulus)
        addmod384(r_1, y_0, y_1, modulus)
    }

    // r <- x - y
    function f2m_sub(x_0, x_1, y_0, y_1, r_0, r_1, modulus, arena) {
        memcpy_384(r_0, x_0)
        memcpy_384(r_1, x_1)
        submod384(r_0, x_0, y_0, modulus)
        submod384(r_1, y_0, y_1, modulus)
    }

    // r <- x * y
    function f2m_mul(x0, x1, y0, y1, r0, r1, modulus, inv, mem) {
        /*
        A <- x_0 * y_0
        B <- x_1 * y_1
        D <- y_0 + y_1

        B <- x_1 * y_1

        C <- x_0 + x_1
        C <- D * C
        C <- C - B

        r_0 <- (0 - (x_1 * y_1)) + (x_0 * y_0)
        r_1 <- ((y_0 + y_1) * (x_0 + x_1)) - (x_1 * y_1)
        */


        /*
        r0 <- mulNR(x1y1)
        r0 <- r0 + x0y0
        
        r1 <- y0_y1
        r1 <- r1 * x0x1
        r1 <- r1 - x1y1
        */
        
        let tmp := add(mem, 64)
        let tmp2 := add(tmp, 64)
        let zero := add(tmp2, 64)

        // TODO also cache x0y0 calculation

        // tmp2 = x1y1
        mulmodmont384(tmp2, x1, y1, modulus, inv)

        //r0 = mulNR(tmp2)
        submod384(r0, zero, tmp2, modulus)

        // tmp = x0y0
        mulmodmont384(tmp, x0, y0, modulus, inv)

        //r0 = r0 + tmp (x0y0)
        addmod384(r0, r0, tmp, modulus)

        // r1 -------------------------------------

        // r1 = ((y0 + y1) * (x0 + x1)) - ((x0 * y0) + (x1 * y1))

        // tmp2 <- x1 * y1
        mulmodmont384(tmp2, x1, y1, modulus, inv)

        // tmp2 <- tmp (x0 * y0) + tmp2 (x1 * y1)
        addmod384(tmp2, tmp, tmp2, modulus)

        // tmp = y0 + y1
        addmod384(tmp, y0, y1, modulus)

        // r1 = x0 + x1
        addmod384(r1, x0, x1, modulus)

        // r1 <- r1 (x0 + x1) * tmp (y0 + y1)
        mulmodmont384(r1, r1, tmp, modulus, inv)

        // r1 = r1 [(x0 + x1) * (y0 + y1)] - tmp2 [(x0 * y0) + (x1 * y1)]
        submod384(r1, r1, tmp2, modulus)
    }

    // {r_0, r_1, r_2} <- {a, b, c} * {A, B, C}
    function f6m_mul(abc, ABC, r, modulus, inv, arena) {
        let aA_0 := arena
        let aA_1 := add(aA_0, 64)

        let bB_0 := add(aA_1, 64)
        let bB_1 := add(bB_0, 64)

        let cC_0 := add(bB_1, 64)
        let cC_1 := add(cC_0, 64)

        let tmp1 := add(cC_1, 64)

        arena := add(tmp1, 128)
        // all memory after 'arena' should be unused

        // aA <- a * A
        f2m_mul(abc, add(abc, 64), ABC, add(ABC, 64), aA_0, aA_1, modulus, inv, arena)

        // bB <- b * B
        f2m_mul(add(abc, 128), add(abc, 192), add(ABC, 128), add(ABC, 192), bB_0, bB_1, modulus, inv, arena)

        // cC <- c * C
        f2m_mul(add(abc, 256), add(abc, 320), add(ABC, 256), add(ABC, 320), cC_0, cC_1, modulus, inv, arena)

        /* 
            r_2 <- ((a + c) * (A + C) - (a * A + c * C)) + bB
        */

        // tmp1 <- a + c
        f2m_add(abc, add(abc, 64), add(abc, 256), add(abc, 320), tmp1, add(tmp1, 64), modulus, arena)

        // r_2 <- A + C
        f2m_add(ABC, add(ABC, 64), add(ABC, 256), add(ABC, 320), add(r, 256), add(r, 320), modulus, arena)
        
        // r_2 <- r_2 * tmp1
        f2m_mul(add(r, 256), add(r, 320), tmp1, add(tmp1, 64), add(r, 256), add(r, 320), modulus, inv, arena)

        // tmp1 <- aA + cC
        f2m_add(aA_0, aA_1, cC_0, cC_1, tmp1, add(tmp1, 64), modulus, arena)

        // r_2 <- r_2 - tmp1
        f2m_sub(add(r, 256), add(r, 320), tmp1, add(tmp1, 64), add(r, 256), add(r, 320), modulus, arena)

        // r_2 <- r_2 + bB
        f2m_add(add(r, 256), add(r, 320), bB_0, bB_1, add(r, 256), add(r, 320), modulus, arena)

        // return(add(r, 256), 128)

        /*
            r1 = ((a_b * A_B) - aA_bB) + mulNonResidue(cC)
        */

        // tmp1 <- a + b
        f2m_add(abc, add(abc, 64), add(abc, 128), add(abc, 192), tmp1, add(tmp1, 64), modulus, arena)
        
        // r_1 <- A + B
        f2m_add(ABC, add(ABC, 64), add(ABC, 128), add(ABC, 192), add(r, 128), add(r, 192), modulus, arena)

        // r_1 <- r_1 * tmp1
        f2m_mul(add(r, 128), add(r, 192), tmp1, add(tmp1, 64), add(r, 128), add(r, 192), modulus, inv, arena)

        // tmp1 <- aA * bB
        f2m_add(aA_0, aA_1, bB_0, bB_1, tmp1, add(tmp1, 64), modulus, arena)

        // r_1 <- r_1 - tmp1
        f2m_sub(add(r, 128), add(r, 192), tmp1, add(tmp1, 64), add(r, 128), add(r, 192), modulus, arena)

        // tmp1 <- mulNonResidue(cC)
        mulNR2(cC_0, cC_1, tmp1, add(tmp1, 64), modulus, arena)

        // r_1 <- r_1 + tmp1
        f2m_add(add(r, 128), add(r, 192), tmp1, add(tmp1, 64), add(r, 128), add(r, 192), modulus, arena)

        /*
            r0 = aA + mulNonResidue((b + c) * (B + C)) - (b * B + c * C))
        */

        // r_0 <- b + c
        f2m_add(add(abc, 128), add(abc, 192), add(abc, 256), add(abc, 320), r, add(r, 64), modulus, arena)

        // tmp1 <- B + C
        f2m_add(add(ABC, 128), add(ABC, 192), add(ABC, 256), add(ABC, 320), tmp1, add(tmp1, 64),  modulus, arena)

        // r_0 <- r_0 * tmp1
        f2m_mul(r, add(r, 64), tmp1, add(tmp1, 64), r, add(r, 64), modulus, inv, arena)

        // tmp1 <- bB + cC
        f2m_add(bB_0, bB_1, cC_0, cC_1, tmp1, add(tmp1, 64), modulus, arena)

        // r_0 seems to be correctly calculated until the following statements

        // r_0 <- r_0 - tmp1
        f2m_sub(r, add(r, 64), tmp1, add(tmp1, 64), r, add(r, 64), modulus, arena)

        // return(r, 128)
        // ^ this line causes "stack too deep" error

        // r_0 <- mulNonResidue(r_0)
        mulNR2(r, add(r, 64), r, add(r, 64), modulus, arena)

        // r_0 <- aA + r_0
        f2m_add(r, add(r, 64), aA_0, aA_1, r, add(r, 64), modulus, arena)
    }

    function test_f6m_mul() {
            let bls12_mod := msize()
            mstore(bls12_mod,          0xabaafffffffffeb9ffff53b1feffab1e24f6b0f6a0d23067bf1285f3844b7764)
            mstore(add(bls12_mod, 32), 0xd7ac4b43b6a71b4b9ae67f39ea11011a00000000000000000000000000000000)

            let point1_a := add(bls12_mod, 384)

            /*
            p1 bytecode

            8f2990f3e598f5b1b8f480a3c388306bc023fac151c0104d13ec3aa18159940272d1c8c528a1ce3bcaa280a8e735aa0d992d7a27906d4cd530b23a7e8c48c0778f8653fbc3332d63db24339d8bc65d7ee83b6e91c6550f5aceab102e88e918097299907146816f08c4c6a394e91374ed6ff3618a57358cfb124ee6ab4c560e5cac40700b41e2ee8674680728f0c5a6180fd77f62b39eb952a0f8d21cec1f93b1d62dd7923aa86882ddf7dd4d3532b0b7ede8f3fc89fa4a79574067e2d9a9d2007a69de46b13d8cb4c4833224aaf9ef7ea6a48975ab35c6e123b8539ab84c381a2533401a73c4e79f47d714899d01ac13a9fa0b0d8156c36a1a9ddacb73ef278f4d149b560e88789f2bfeb9f708b6cc2f988927bfe0186d5bf9cb40cb07f21b18

            p2 bytecode

            ecd347c808af644c7a3a971a556576f434e302b6b490004fb418a4a7da330a6743adeca931169b8b92e91df73ae1e11512a2829e11e843d764d5e3b80e75432d93f69b23ad79c38d43ebbc9bd2b17b9e903033351357b03602624762e5ad360dd7f9857dce663301f393f9fac66f5c49168494e0d20797a6c4f96327ed4fa47dd36d0078d217a712407d35046871d40f2f1b767f6c1ec190eb76a0bce7906ad2e4a7548d03e8aa745e34e1bf49d83ad64c04f57fb4d31039cb4cf01987fda2137b3f8da2f2ae47885890b0d433a3eeed2f9f37cbcfc444e4f1d880390fcdb76518d558857be01b2b10a8010bcdc6d606319c02f6132c8a786377868b5825ada9a5fe303e9ae3b03ce56e90734a17ce970c88b321012cf8dabb58211e3d50f610
            */

            /*

            // values are in little-endian (as expected by the EVM384 opcodes)
            p1:
                (('8f2990f3e598f5b1b8f480a3c388306bc023fac151c0104d13ec3aa18159940272d1c8c528a1ce3bcaa280a8e735aa0d', '992d7a27906d4cd530b23a7e8c48c0778f8653fbc3332d63db24339d8bc65d7ee83b6e91c6550f5aceab102e88e91809'), ('7299907146816f08c4c6a394e91374ed6ff3618a57358cfb124ee6ab4c560e5cac40700b41e2ee8674680728f0c5a618', '0fd77f62b39eb952a0f8d21cec1f93b1d62dd7923aa86882ddf7dd4d3532b0b7ede8f3fc89fa4a79574067e2d9a9d200'), ('7a69de46b13d8cb4c4833224aaf9ef7ea6a48975ab35c6e123b8539ab84c381a2533401a73c4e79f47d714899d01ac13', 'a9fa0b0d8156c36a1a9ddacb73ef278f4d149b560e88789f2bfeb9f708b6cc2f988927bfe0186d5bf9cb40cb07f21b18'))
            p2:
                (('ecd347c808af644c7a3a971a556576f434e302b6b490004fb418a4a7da330a6743adeca931169b8b92e91df73ae1e115', '12a2829e11e843d764d5e3b80e75432d93f69b23ad79c38d43ebbc9bd2b17b9e903033351357b03602624762e5ad360d'), ('d7f9857dce663301f393f9fac66f5c49168494e0d20797a6c4f96327ed4fa47dd36d0078d217a712407d35046871d40f', '2f1b767f6c1ec190eb76a0bce7906ad2e4a7548d03e8aa745e34e1bf49d83ad64c04f57fb4d31039cb4cf01987fda213'), ('7b3f8da2f2ae47885890b0d433a3eeed2f9f37cbcfc444e4f1d880390fcdb76518d558857be01b2b10a8010bcdc6d606', '319c02f6132c8a786377868b5825ada9a5fe303e9ae3b03ce56e90734a17ce970c88b321012cf8dabb58211e3d50f610'))

            */

            mstore(point1_a,          0x8f2990f3e598f5b1b8f480a3c388306bc023fac151c0104d13ec3aa181599402)
            mstore(add(point1_a, 32), 0x72d1c8c528a1ce3bcaa280a8e735aa0d00000000000000000000000000000000)
            mstore(add(point1_a, 64), 0x992d7a27906d4cd530b23a7e8c48c0778f8653fbc3332d63db24339d8bc65d7e)
            mstore(add(point1_a, 96), 0xe83b6e91c6550f5aceab102e88e9180900000000000000000000000000000000)

            let point1_b := add(point1_a, 128)
            mstore(point1_b,          0x7299907146816f08c4c6a394e91374ed6ff3618a57358cfb124ee6ab4c560e5c)
            mstore(add(point1_b, 32), 0xac40700b41e2ee8674680728f0c5a61800000000000000000000000000000000)
            mstore(add(point1_b, 64), 0x0fd77f62b39eb952a0f8d21cec1f93b1d62dd7923aa86882ddf7dd4d3532b0b7)
            mstore(add(point1_b, 96), 0xede8f3fc89fa4a79574067e2d9a9d20000000000000000000000000000000000)

            let point1_c := add(point1_b, 128)
            mstore(point1_c,          0x7a69de46b13d8cb4c4833224aaf9ef7ea6a48975ab35c6e123b8539ab84c381a)
            mstore(add(point1_c, 32), 0x2533401a73c4e79f47d714899d01ac1300000000000000000000000000000000)
            mstore(add(point1_c, 64), 0xa9fa0b0d8156c36a1a9ddacb73ef278f4d149b560e88789f2bfeb9f708b6cc2f)
            mstore(add(point1_c, 96), 0x988927bfe0186d5bf9cb40cb07f21b1800000000000000000000000000000000)

            let point2_A := add(point1_c, 128)
            mstore(point2_A,          0xecd347c808af644c7a3a971a556576f434e302b6b490004fb418a4a7da330a67)
            mstore(add(point2_A, 32), 0x43adeca931169b8b92e91df73ae1e11500000000000000000000000000000000)
            mstore(add(point2_A, 64), 0x12a2829e11e843d764d5e3b80e75432d93f69b23ad79c38d43ebbc9bd2b17b9e)
            mstore(add(point2_A, 96), 0x903033351357b03602624762e5ad360d00000000000000000000000000000000)

            let point2_B := add(point2_A, 128)
            mstore(point2_B,          0xd7f9857dce663301f393f9fac66f5c49168494e0d20797a6c4f96327ed4fa47d)
            mstore(add(point2_B, 32), 0xd36d0078d217a712407d35046871d40f00000000000000000000000000000000)
            mstore(add(point2_B, 64), 0x2f1b767f6c1ec190eb76a0bce7906ad2e4a7548d03e8aa745e34e1bf49d83ad6)
            mstore(add(point2_B, 96), 0x4c04f57fb4d31039cb4cf01987fda21300000000000000000000000000000000)

            let point2_C := add(point2_B, 128)
            mstore(point2_C,          0x7b3f8da2f2ae47885890b0d433a3eeed2f9f37cbcfc444e4f1d880390fcdb765)
            mstore(add(point2_C, 32), 0x18d558857be01b2b10a8010bcdc6d60600000000000000000000000000000000)
            mstore(add(point2_C, 64), 0x319c02f6132c8a786377868b5825ada9a5fe303e9ae3b03ce56e90734a17ce97)
            mstore(add(point2_C, 96), 0x0c88b321012cf8dabb58211e3d50f61000000000000000000000000000000000)


            let f6m_result1 := add(point2_C, 384) // allocate memory past bls12_mod
            let f6m_result2 := add(f6m_result1, 384)
            let f6m_result3 := add(f6m_result2, 384)
            let f6m_result4 := add(f6m_result3, 384)
            let f6m_result5 := add(f6m_result4, 384)

            let f6m_scratch_space := add(f6m_result5, 384)

            let bls12_r_inv := 0x89f3fffcfffcfffd

            //f6m_mul(a, A, r_0, bls12_mod, bls12_r_inv, add(bls12_mod, 128))

            f6m_mul(point1_a, point2_A, f6m_result1, bls12_mod, bls12_r_inv, f6m_scratch_space)
            return(f6m_result1, 64)


            /*
            f6m_mul(point1_a, point2_A, f6m_result4, bls12_mod, bls12_r_inv, f6m_scratch_space)
            f6m_mul(point1_a, f6m_result4, f6m_result5, bls12_mod, bls12_r_inv, f6m_scratch_space)

            let i := 0
            for {} lt(i, 10) {i := add(i, 1)} {            
                f6m_mul(f6m_result4, f6m_result5, f6m_result1, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result5, f6m_result1, f6m_result2, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result1, f6m_result2, f6m_result3, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result2, f6m_result3, f6m_result4, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result3, f6m_result4, f6m_result5, bls12_mod, bls12_r_inv, f6m_scratch_space)

                f6m_mul(f6m_result4, f6m_result5, f6m_result1, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result5, f6m_result1, f6m_result2, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result1, f6m_result2, f6m_result3, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result2, f6m_result3, f6m_result4, bls12_mod, bls12_r_inv, f6m_scratch_space)
                f6m_mul(f6m_result3, f6m_result4, f6m_result5, bls12_mod, bls12_r_inv, f6m_scratch_space)
            }

            return(f6m_result5, 64)
            */

    }


    function test_f2m_mul() {
    /*
        8f2990f3e598f5b1b8f480a3c388306bc023fac151c0104d13ec3aa18159940272d1c8c528a1ce3bcaa280a8e735aa0d992d7a27906d4cd530b23a7e8c48c0778f8653fbc3332d63db24339d8bc65d7ee83b6e91c6550f5aceab102e88e918097299907146816f08c4c6a394e91374ed6ff3618a57358cfb124ee6ab4c560e5cac40700b41e2ee8674680728f0c5a618 *
        ecd347c808af644c7a3a971a556576f434e302b6b490004fb418a4a7da330a6743adeca931169b8b92e91df73ae1e11512a2829e11e843d764d5e3b80e75432d93f69b23ad79c38d43ebbc9bd2b17b9e903033351357b03602624762e5ad360dd7f9857dce663301f393f9fac66f5c49168494e0d20797a6c4f96327ed4fa47dd36d0078d217a712407d35046871d40f =

        1a984f235709ab3941e22b5e67d5ba892ce9242e227c0c6bb38aa1ace4d4b64aaba753d350d98f4c05570f525d67a901b1297e4e9ca0c757dfe693ea0d2f5216daeaa4ad06964e2f7c242200049d386d860b25d4718a2c4240fb89c90abe4e10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    */
            let mem := msize()

            let bls12_mod := mem
            mstore(bls12_mod,          0xabaafffffffffeb9ffff53b1feffab1e24f6b0f6a0d23067bf1285f3844b7764)
            mstore(add(bls12_mod, 32), 0xd7ac4b43b6a71b4b9ae67f39ea11011a00000000000000000000000000000000)

            let bls12_r_inv :=         0x89f3fffcfffcfffd


            let x := add(bls12_mod, 128)
            mstore(x,          0x8f2990f3e598f5b1b8f480a3c388306bc023fac151c0104d13ec3aa181599402)
            mstore(add(x, 32), 0x72d1c8c528a1ce3bcaa280a8e735aa0d00000000000000000000000000000000)
            mstore(add(x, 64), 0x992d7a27906d4cd530b23a7e8c48c0778f8653fbc3332d63db24339d8bc65d7e)
            mstore(add(x, 96), 0xe83b6e91c6550f5aceab102e88e9180900000000000000000000000000000000)

            let y := add(x, 128)
            mstore(y,          0xecd347c808af644c7a3a971a556576f434e302b6b490004fb418a4a7da330a67)
            mstore(add(y, 32), 0x43adeca931169b8b92e91df73ae1e11500000000000000000000000000000000)
            mstore(add(y, 64), 0x12a2829e11e843d764d5e3b80e75432d93f69b23ad79c38d43ebbc9bd2b17b9e)
            mstore(add(y, 96), 0x903033351357b03602624762e5ad360d00000000000000000000000000000000)

            let r := add(y, 128)

            f2m_mul(x, add(x, 64), y, add(y, 64), r, add(r, 64), bls12_mod, bls12_r_inv, add(r, 128))

            if eq(eq(mload(r), 0x1a984f235709ab3941e22b5e67d5ba892ce9242e227c0c6bb38aa1ace4d4b64a), false) {
                revert(0,0)
            }

            if eq(eq(mload(add(r, 32)), 0xaba753d350d98f4c05570f525d67a90100000000000000000000000000000000), false) {
                revert(0,0)
            }

            if eq(eq(mload(add(r, 64)), 0xb1297e4e9ca0c757dfe693ea0d2f5216daeaa4ad06964e2f7c242200049d386d), false) {
                revert(0,0)
            }

            if eq(eq(mload(add(r, 96)), 0x860b25d4718a2c4240fb89c90abe4e1000000000000000000000000000000000), false) {
                revert(0,0)
            }
    }

    test_f6m_mul()
    //test_f2m_mul()
}
