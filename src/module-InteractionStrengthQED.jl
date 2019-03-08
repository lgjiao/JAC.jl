
"""
`module  JAC.InteractionStrengthQED`  ... a submodel of JAC that contains methods for computing local single-electron QED corrections; 
                                          it is using JAC, JAC.ManyElectron, JAC.Radial.
"""
module InteractionStrengthQED

    using Printf, JAC, JAC.Radial


    """
    `JAC.InteractionStrengthQED.qedLocal(a::Orbital, b::Orbital, nm::JAC.Nuclear.Model, pot::Radial.Potential, grid::Radial.Grid)`  
        ... to calculate the local, single-electron QED correction due to a chosen QedModel.  The function also determines whether 
            the 'stored' hydrogenic values for the lambda_C-dampled overlap integrals belong the given Z-value, and re-calculates 
            these overlap integrals whenever necessary.  A single-electron amplitud wa::Float64 is returned.
    """
    function qedLocal(a::Orbital, b::Orbital, nm::JAC.Nuclear.Model, pot::Radial.Potential, grid::Radial.Grid)
        global  JAC_QED_MODEL,  JAC_QED_NUCLEAR_CHARGE,  JAC_QED_HYDROGENIC_LAMBDAC
        # Define a grid for the t-integration
        qgrid = JAC.Radial.GridGL("QED",  7)
        # Re-define the hydrogenic values of the 
        if  nm.Z != JAC.JAC_QED_NUCLEAR_CHARGE
            alpha = JAC.give("alpha")
            ax  = JAC.HydrogenicIon.radialOrbital(Subshell("1s_1/2"), nm.Z, grid);    wc1 = JAC.RadialIntegrals.qedDampedOverlap(alpha, ax, ax, grid)
            ax  = JAC.HydrogenicIon.radialOrbital(Subshell("2p_1/2"), nm.Z, grid);    wc2 = JAC.RadialIntegrals.qedDampedOverlap(alpha, ax, ax, grid)
            ax  = JAC.HydrogenicIon.radialOrbital(Subshell("2p_3/2"), nm.Z, grid);    wc3 = JAC.RadialIntegrals.qedDampedOverlap(alpha, ax, ax, grid)
            ax  = JAC.HydrogenicIon.radialOrbital(Subshell("3d_3/2"), nm.Z, grid);    wc4 = JAC.RadialIntegrals.qedDampedOverlap(alpha, ax, ax, grid)
            ax  = JAC.HydrogenicIon.radialOrbital(Subshell("3d_5/2"), nm.Z, grid);    wc5 = JAC.RadialIntegrals.qedDampedOverlap(alpha, ax, ax, grid)
            JAC.define("QED: damped-hydrogenic", nm.Z, [wc1, wc2, wc3, wc4, wc5] )
            println("Redefined damped radial integrals JAC_QED_HYDROGENIC_LAMBDAC = $(JAC.JAC_QED_HYDROGENIC_LAMBDAC)")
        end
        
        if      JAC.JAC_QED_MODEL == QedSydney
            wa = JAC.RadialIntegrals.qedUehlingSimple(a, b, pot, grid, qgrid) + 
                 ## JAC.RadialIntegrals.qedWichmannKrollSimple(a, b, pot, grid, qgrid) + 
                 ## JAC.RadialIntegrals.qedElectricFormFactor(a, b, pot, grid, qgrid) + 
                 ## JAC.RadialIntegrals.qedMagneticFormFactor(a, b, pot, grid, qgrid) + 
                 JAC.RadialIntegrals.qedLowFrequency(a, b, nm, grid, qgrid) 
        elseif  JAC.JAC_QED_MODEL == QedPetersburg
            wa = JAC.RadialIntegrals.qedUehlingSimple(a, b, pot, grid, qgrid) + 
                 JAC.InteractionStrengthQED.selfEnergyVolotka(a, b, nm, pot, grid, qgrid)
        else    error("stop a")
        end
        return( wa )
    end


    """
    `JAC.InteractionStrengthQED.selfEnergyVolotka(a::Orbital, b::Orbital, nm::JAC.Nuclear.Model, 
                                                  pot::Radial.Potential, grid::Radial.Grid,qgrid::Radial.GridGL)`
        ... to calculate the local, single-electron self-energy contribution due to the Petersburg model (PRA, 2013), further
        simplified by Andrey Volotka. A non-zero self-energy contribution is returned only for orbitals with 1 <= n <= 4 and 
        kappa = -1, 1, -2, 2, -3, since the method appears rather inaccurate for higher (n, kappa). 
        A single-electron self-energy amplitude wa::Float64 is returned.
    """
    function selfEnergyVolotka(a::Orbital, b::Orbital, nm::JAC.Nuclear.Model, pot::Radial.Potential, grid::Radial.Grid,qgrid::Radial.GridGL)
        # Non-zero local amplitudes only for kappa_a = kappa_b
        if      a.subshell != b.subshell  ||  a.subshell.n > 4   return( 0. )    end
        
        if      a.subshell.kappa == -1   nn = 1;    elseif  a.subshell.kappa ==  1   nn = 2;    elseif  a.subshell.kappa == -2   nn = 2
        elseif  a.subshell.kappa ==  2   nn = 3;    elseif  a.subshell.kappa == -3   nn = 3
        else    error("stop a")
        end
        
        alpha       = JAC.give("alpha");  
        whydrogenic = JAC.InteractionStrengthQED.tabulateFzeOverHydrogenic(nm.Z, a.subshell) * alpha / pi * (alpha*nm.Z)^4 / nn^3 / alpha^2
        wb          = JAC.RadialIntegrals.qedDampedOverlap(alpha, a, a, grid)
        wa          = whydrogenic * wb
        
        # Printout the corresponding  F(alpha Z) value for the given orbital if a == b
        ## FalphaZ = alpha/pi * (alpha*nm.Z)^4 / a.subshell.n^3 / alpha^2
        ## FalphaZ = wa / FalphaZ
        ## println("Self-energy function for $(a.subshell) and $(a.subshell) is F(alpha Z) = $FalphaZ,  wdamped = $wb,  wa = $wa ")
        
        println("QED single-electron strength <$(a.subshell)| h^(SE, Volotka) | $(b.subshell)> = $wa ")
        
        return( wa )
    end


    """
    `JAC.InteractionStrengthQED.tabulateFzeOverHydrogenic(Z::Float64, sh::Subshell)`  
        ... to return the value of the FZE() table as shown by Shabaev et al., PRA 88, 012513  (2013) but just for the lowest 
            possible subshell of a given kappa-value; this tabulated value is devided by the lambda_C-dampled overlap integral,
            calculated with hydrogenic functions; a Float64 is returned. The table below only includes the data for extended
            nuclei, if available in the tabulations above, while a point-nucleus was assumed otherwise. All these data
            are calculated with hydrogenic function and, hence, need to be 're-scaled' for many-electron ions and atoms
            (as realized for these local, single-electron amplitudes). 
    """
    function tabulateFzeOverHydrogenic(Z::Float64, sh::Subshell)
        global  fez_qed
        # Select the proper column from the table
        if      sh.kappa == -1   k = 1;    elseif  sh.kappa ==  1   k = 2;    elseif  sh.kappa == -2   k = 3
        elseif  sh.kappa ==  2   k = 4;    elseif  sh.kappa == -3   k = 5
        else    error("stop a")
        end
        #  Select the proper raw from the table
        if        1.0 <= Z <  10.0    return( 0. )
        elseif   10.0 <= Z <  20.0    wa =  fez_qed[1,k] + (Z -  10.) / 10. *( fez_qed[2,k] -  fez_qed[1,k])
        elseif   20.0 <= Z <  30.0    wa =  fez_qed[2,k] + (Z -  20.) / 10. *( fez_qed[3,k] -  fez_qed[2,k])
        elseif   30.0 <= Z <  40.0    wa =  fez_qed[3,k] + (Z -  30.) / 10. *( fez_qed[4,k] -  fez_qed[3,k])
        elseif   40.0 <= Z <  50.0    wa =  fez_qed[4,k] + (Z -  40.) / 10. *( fez_qed[5,k] -  fez_qed[4,k])
        elseif   50.0 <= Z <  60.0    wa =  fez_qed[5,k] + (Z -  50.) / 10. *( fez_qed[6,k] -  fez_qed[5,k])
        elseif   60.0 <= Z <  70.0    wa =  fez_qed[6,k] + (Z -  60.) / 10. *( fez_qed[7,k] -  fez_qed[6,k])
        elseif   70.0 <= Z <  80.0    wa =  fez_qed[7,k] + (Z -  70.) / 10. *( fez_qed[8,k] -  fez_qed[7,k])
        elseif   80.0 <= Z <  90.0    wa =  fez_qed[8,k] + (Z -  80.) / 10. *( fez_qed[9,k] -  fez_qed[8,k])
        elseif   90.0 <= Z < 100.0    wa =  fez_qed[9,k] + (Z -  90.) / 10. *(fez_qed[10,k] -  fez_qed[9,k])
        elseif  100.0 <= Z < 110.0    wa = fez_qed[10,k] + (Z - 100.) / 10. *(fez_qed[11,k] - fez_qed[10,k])
        elseif  110.0 <= Z < 120.0    wa = fez_qed[11,k] + (Z - 110.) / 10. *(fez_qed[12,k] - fez_qed[11,k])
        else    error("stop c")
        end
       
        return( wa / JAC.JAC_QED_HYDROGENIC_LAMBDAC[k] )
    end
    
    #                   Z/10       1s_1/2      2p_1/2      2p_3/2      3d_3/2      3d_5/2        Zi
    const   fez_qed =         [    4.6542     -0.1148      0.1304     -0.0427      0.0408   ;   #  10
                                   3.2462     -0.0925      0.1438     -0.0420      0.0417   ;   #  20
                                   2.5518     -0.0643      0.1606     -0.0410      0.0432   ;   #  30
                                   2.1347     -0.0310      0.1796     -0.0396      0.0452   ;   #  40
                                   1.8633      0.0080      0.2001     -0.0378      0.0475   ;   #  50
                                   1.6820      0.0547      0.2216     -0.0353      0.0503   ;   #  60
                                   1.5637      0.1126      0.2441     -0.0321      0.0536   ;   #  70
                                   1.4955      0.1877      0.2671     -0.0279      0.0572   ;   #  80
                                   1.4721      0.2912      0.2904     -0.0229      0.0612   ;   #  90
                                   1.4961      0.4450      0.3135     -0.0154      0.0654   ;   # 100
                                   1.5771      0.6961      0.3356     -0.0063      0.0699   ;   # 110
                                   1.7335      1.1559      0.3548      0.0051      0.0745   ]   # 120
    

end # module

