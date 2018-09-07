#*****************************************************************************
#
#    Tools to compute Hilbert Poincaré series of monomial ideals
#
#    Copyright (C) 2018 Simon A. King <simon.king@uni-jena.de>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#                  http://www.gnu.org/licenses/
#
#*****************************************************************************

from sage.all import Integer, ZZ, QQ, PolynomialRing
from sage.stats.basic_stats import median
from sage.rings.polynomial.polydict cimport ETuple
from sage.interfaces.singular import Singular

from cysignals.memory cimport sig_malloc

# Global definition
PR = PolynomialRing(ZZ,'t')
t = PR('t')

###
#   cdef functions concerning algebraic properties of monomials
###

cdef inline bint divides(ETuple m1, ETuple m2):
    "Whether m1 divides m2, i.e., no entry of m1 exceeds m2."
    cdef size_t ind1     # will be increased in 2-steps
    cdef size_t ind2 = 0 # will be increased in 2-steps
    cdef int pos1, exp1
    if m1._nonzero > m2._nonzero:
        # Trivially m1 cannot divide m2
        return False
    cdef size_t m2nz2 = 2*m2._nonzero
    for ind1 from 0 <= ind1 < 2*m1._nonzero by 2:
        pos1 = m1._data[ind1]
        exp1 = m1._data[ind1+1]
        # Because of the above trivial test, m2._nonzero>0.
        # So, m2._data[ind2] initially makes sense.
        while m2._data[ind2] < pos1:
            ind2 += 2
            if ind2 >= m2nz2:
                return False
        if m2._data[ind2] > pos1 or m2._data[ind2+1] < exp1:
            # Either m2 has no exponent at position pos1 or the exponent is less than in m1
            return False
    return True

cdef ETuple divide_by_gcd(ETuple m1, ETuple m2):
    """Return ``m1/gcd(m1,m2)``.

    The entries of the result are the maximum of 0 and
    the difference of the corresponding entries of ``m1`` and ``m2``.
    """
    cdef size_t ind1 = 0    # both ind1 and ind2 will be increased in 2-steps.
    cdef size_t ind2 = 0
    cdef int exponent
    cdef int position
    cdef size_t m1nz = 2*m1._nonzero
    cdef size_t m2nz = 2*m2._nonzero
    cdef ETuple result = <ETuple>m1._new()
    result._nonzero = 0
    result._data = <int*>sig_malloc(sizeof(int)*m1._nonzero*2)
    while ind1 < m1nz:
        position = m1._data[ind1]
        exponent = m1._data[ind1+1]
        while ind2 < m2nz and m2._data[ind2] < position:
            ind2 += 2
        if ind2 == m2nz:
            while ind1 < m1nz:
                result._data[2*result._nonzero] = m1._data[ind1]
                result._data[2*result._nonzero+1] = m1._data[ind1+1]
                result._nonzero += 1
                ind1 += 2
            return result
        if m2._data[ind2] > position:
            # m2[position] == 0
            result._data[2*result._nonzero] = position
            result._data[2*result._nonzero+1] = exponent
            result._nonzero += 1
        elif m2._data[ind2+1] < exponent:
            # There is a positive difference that we have to insert
            result._data[2*result._nonzero] = position
            result._data[2*result._nonzero+1] = exponent - m2._data[ind2+1]
            result._nonzero += 1
        ind1 += 2
    return result

cdef ETuple divide_by_var(ETuple m1, size_t index):
    """Return division of ``m1`` by ``var(index)``, or None.

    If ``m1[Index]==0`` then None is returned. Otherwise, an :class:`~sage.rings.polynomial.polydict.ETuple`
    is returned that is zero in positition ``index`` and coincides with ``m1``
    in the other positions.
    """
    cdef size_t i,j
    cdef int exp1
    cdef ETuple result
    for i from 0 <= i < 2*m1._nonzero by 2:
        if m1._data[i] == index:
            result = <ETuple>m1._new()
            result._data = <int*>sig_malloc(sizeof(int)*m1._nonzero*2)
            exp1 = m1._data[i+1]
            if exp1>1:
                # division doesn't change the number of nonzero positions
                result._nonzero = m1._nonzero
                for j from 0 <= j < 2*m1._nonzero by 2:
                    result._data[j] = m1._data[j]
                    result._data[j+1] = m1._data[j+1]
                result._data[i+1] = exp1-1
            else:
                # var(index) disappears from m1
                result._nonzero = m1._nonzero-1
                for j from 0 <= j < i by 2:
                    result._data[j] = m1._data[j]
                    result._data[j+1] = m1._data[j+1]
                for j from i+2 <= j < 2*m1._nonzero by 2:
                    result._data[j-2] = m1._data[j]
                    result._data[j-1] = m1._data[j+1]
            return result
    return None

cpdef inline size_t total_unweighted_degree(ETuple m):
    "Return the sum of the entries"
    cdef size_t degree = 0
    cdef size_t i
    for i from 0 <= i < 2*m._nonzero by 2:
        degree += m._data[i+1]
    return degree

cdef size_t quotient_degree(ETuple m1, ETuple m2, tuple w) except 0:
    cdef size_t ind1 = 0    # both ind1 and ind2 will be increased in double steps.
    cdef size_t ind2 = 0
    cdef int exponent
    cdef int position
    cdef size_t m1nz = 2*m1._nonzero
    cdef size_t m2nz = 2*m2._nonzero

    cdef size_t deg = 0
    if w is None:
        while ind1 < m1nz:
            position = m1._data[ind1]
            exponent = m1._data[ind1+1]
            while ind2 < m2nz and m2._data[ind2] < position:
                ind2 += 2
            if ind2 == m2nz:
                while ind1 < m1nz:
                    deg += m1._data[ind1+1]
                    ind1 += 2
                return deg
            if m2._data[ind2] > position:
                # m2[position] = 0
                deg += exponent
            elif m2._data[ind2+1] < exponent:
                # There is a positive difference that we have to insert
                deg += (exponent - m2._data[ind2+1])
            ind1 += 2
        return deg
    while ind1 < m1nz:
        position = m1._data[ind1]
        exponent = m1._data[ind1+1]
        while ind2 < m2nz and m2._data[ind2] < position:
            ind2 += 2
        if ind2 == m2nz:
            while ind1 < m1nz:
                deg += m1._data[ind1+1] * w[m1._data[ind1]]
                ind1 += 2
            return deg
        if m2._data[ind2] > position:
            # m2[position] = 0
            deg += exponent * w[position]
        elif m2._data[ind2+1] < exponent:
            # There is a positive difference that we have to insert
            deg += (exponent - m2._data[ind2+1]) * w[position]
        ind1 += 2
    return deg

cdef inline size_t degree(ETuple m, tuple w):
    cdef size_t i
    cdef size_t deg = 0
    if w is None:
        for i from 0 <= i < 2*m._nonzero by 2:
            deg += m._data[i+1]
    else:
        for i from 0 <= i < 2*m._nonzero by 2:
            deg += m._data[i+1]*w[m._data[i]]
    return deg

###
#   cdef functions related with lists of monomials
###

cdef inline bint indivisible_in_list(ETuple m, list L, size_t i):
    "Is m divisible by any monomial in L[:i]?"
    cdef size_t j
    for j in range(i):
        if divides(L[j],m):
            return False
    return True

cdef inline list interred(list L):
    """Return interreduction of a list of monomials.

    NOTE::

        The given list will be sorted in-place

    INPUT::

    A list of :class:`~sage.rings.polynomial.polydict.ETuple`.

    OUTPUT::

    The interreduced list, where we interprete each ETuple as
    a monomial in a multivariate ring.
    """
    # First, we sort L ascendingly by total unweighted degree.
    # Afterwards, no monomial in L is divisible by a monomial
    # that appears later in L.
    if not L:
        return []
    L.sort(key=total_unweighted_degree)
    cdef size_t i
    cdef list result = [L[0]]
    for i in range(1,len(L)):
        m = L[i]
        if indivisible_in_list(m, L, i):
            result.append(m)
    return result

cdef quotient(list L, ETuple m):
    "Return the quotient of the ideal represented by L and the monomial represented by m"
    cdef ETuple m_i
    cdef list result = list(L)
    for m_i in L:
        result.append(divide_by_gcd(m_i,m))
    return interred(result)

cdef quotient_by_var(list L, size_t index):
    "Return the quotient of the ideal represented by L and the variable number ``index``"
    cdef ETuple m_i,m_j
    cdef list result = list(L) # creates a copy
    for m_i in L:
        m_j = divide_by_var(m_i,index)
        if m_j is not None:
            result.append(m_j)
    return interred(result)

cdef ETuple sum_from_list(list L, size_t l):
    """Compute the vector sum of the ETuples in L in a balanced way.

    For efficiency, the length of L must be provided as second parameter.
    """
    cdef ETuple m1,m2
    if l==1:
        m1 = L[0]
        return L[0]
    if l==2:
        m1,m2=L
        return m1.eadd(m2)
    cdef size_t l2 = l//2
    m1 = sum_from_list(L[:l2], l2)
    m2 = sum_from_list(L[l2:], l-l2)
    return m1.eadd(m2)

cpdef HilbertBaseCase(dict D, tuple w):
    """
    Try to compute the first Hilbert series of ``D['Id']``, or return ``NotImplemented``.

    The second parameter is a tuple of integers, the degree weights to be used.

    In some base cases, the value of the Hilbert series will be directly returned.
    If the ideal is not one of the base cases, then ``NotImplemented``
    is returned.

    """
    cdef list Id = D['Id']
    cdef size_t i,j
    cdef int e
    # First, the easiest cases:
    if len(Id)==0:
        return PR(1)
    cdef ETuple m = Id[-1]
    if m._nonzero == 0:
        return PR(0)

    # Second, another reasy case: Id is generated by variables.
    # Id is sorted ascendingly. Hence, if the last generator is a single
    # variable, then ALL are.
    if m._nonzero==1 and m._data[1]==1:
        return PR.prod([(1-t**degree(m,w)) for m in Id])

    # Thirdly, we test for proper powers of single variables.
    cdef bint easy = True
    for i,m in enumerate(Id):
        if m._nonzero > 1: # i.e., the generator contains more than a single var
            easy = False
            break
    if easy:
        # The ideal is generated by some powers of single variables, i.e., it splits.
        return PR.prod([(1-t**degree(m,w)) for m in Id])

    easy = True
    cdef list v
    for j in range(i+1,len(Id)):
        m = Id[j]
        if m._nonzero>1: # i.e., another generator contains more than a single var
            easy = False
            break
    cdef ETuple m2
    if easy:
        # The ideal only has a single non-simple power, in position i.
        # Since the ideal is interreduced and all other monomials are
        # simple powers, we have the following formula
        m = Id[i]
        Factor = PR.one()
        for m2 in Id:
            if m is not m2:
                Factor *= (1-t**quotient_degree(m2,m,w))
        return PR.prod([(1-t**degree(m2,w)) for m2 in Id if m2 is not m]) - t**degree(m,w)*Factor
    # We are in a truly difficult case and give up for now...
    return NotImplemented

cdef make_children(dict D, tuple w):
    """
    Create child nodes in ``D`` that allow to compute the first Hilbert series of ``D['Id']``
    """
    cdef list Id = D['Id']
    cdef size_t j,m
    cdef int i,ii
    # Determine the variable that appears most often in the monomials.
    # If "most often" means "only once", then instead we choose a variable that is
    # guaranteed to appear in a composed monomial.
    # We will raise it to a reasonably high power that still guarantees that
    # many monomials will be divisible by it.
    cdef ETuple all_exponents = sum_from_list(Id, len(Id))
    m = 0
    cdef list max_exponents = []
    for i from 0 <= i < 2*all_exponents._nonzero by 2:
        j = all_exponents._data[i+1]
        if j>m:
            max_exponents = [all_exponents._data[i]]
            m = j
        elif j==m:
            max_exponents.append(all_exponents._data[i])
    cdef size_t e # will be the exponent, if the monomial used for cutting is power of a variable
    cdef ETuple cut,mon
    cdef list Id2
    # Cases:
    # - m==1, which means that all variables occur at most once.
    #   => we cut by a variable that appears in a decomposable generator
    # - max_exponents = [j]
    #   => cut = var(j)**e, where e is the median of all j-exponents
    # - max_exponents = [j1,...,jk]
    #   => cut = prod([var(j1),...,var(jk)]) or something of that type.
    if m == 1:
        all_exponents = Id[-1]  # Id is sorted, which means that the last generator is decomposable
        j = all_exponents._data[2*all_exponents._nonzero-2]
        cut = all_exponents._new()
        cut._nonzero = 1
        cut._data = <int*>sig_malloc(sizeof(int)*2)
        cut._data[0] = j
        cut._data[1] = 1
        # var(j) *only* appears in Id[-1]. Hence, Id+var(j) will be a split case,
        # with var(j) and Id[:-1]. So, we do the splitting right now.
        # Only the last generator contains var(j). Hence, Id/var(j) is obtained
        # from Id by adding the quotient of its last generator divided by var(j),
        # of course followed by interreduction.
        D['LMult'] = 1-t**degree(cut,w)
        D['Left']  = {'Id':Id[:-1], 'Back':D}
        Id2 = Id[:-1]
        Id2.append(divide_by_var(Id[-1],j))
        D['Right'] = {'Id':interred(Id2), 'Back':D}
        D['RMult'] = 1-D['LMult']
    else:
        j = max_exponents[0]
        e = median([mon[j] for mon in Id if mon[j]])
        cut = all_exponents._new()
        cut._nonzero = 1
        cut._data = <int*>sig_malloc(sizeof(int)*2)
        cut._data[0] = j
        cut._data[1] = e
        try:
            i = Id.index(cut)
        except ValueError:
            i = -1
        if i>=0:
            # var(j)**e is a generator. Hence, e is the maximal exponent of var(j) in Id, by
            # Id being interreduced. But it also is the truncated median, hence, there cannot
            # be smaller exponents (for otherwise the median would be strictly smaller than the maximum).
            # Conclusion: var(j) only appears in the generator var(j)**e -- we have a split case.
            Id2 = list(Id)
            Id2.pop(i)
            D['LMult'] = 1-t**degree(cut,w)
            D['Left']  = {'Id':Id2, 'Back':D}
            D['Right'] = None
        else:
            cut = all_exponents._new()
            cut._nonzero = 1
            cut._data = <int*>sig_malloc(sizeof(int)*2)
            cut._data[0] = j
            cut._data[1] = e
            if e>1:
                D['LMult'] = 1
                Id2 = list(Id)
                Id2.append(cut)
                D['Left']  = {'Id':interred(Id2), 'Back':D}
                D['Right'] = {'Id':quotient(Id,cut), 'Back':D}
            else:
                # m>1, therefore var(j) cannot be a generator (Id is interreduced).
                # Id+var(j) will be a split case. So, we do the splitting right now.
                D['LMult'] = 1-t**(1 if w is None else w[j])
                D['Left']  = {'Id':[mon for mon in Id if mon[j]==0], 'Back':D}
                D['Right'] = {'Id':quotient_by_var(Id,j), 'Back':D}
            D['RMult'] = t**(e if w is None else e*w[j])
#~     else:
#~         # It may be a good idea to form the product of some of the most frequent
#~         # variables. But this isn't implemented yet. TODO?

def first_hilbert_series(I, grading=None, return_grading=False):
    """
    Return the first Hilbert series of the given monomial ideal.

    INPUT:

    ``I``: an ideal or its name in singular, weighted homogeneous with respect
           to the degree of the ring variables.
    ``grading`` (optional): A list or tuple of integers used as degree weights
    ``return_grading`` (optional, default False): Whether to return the grading.

    OUTPUT:

    A univariate polynomial, namely the first Hilbert function of ``I``, and
    if ``return_grading==True`` also the grading used to compute the series.

    EXAMPLES::

        sage: from sage.rings.polynomial.hilbert import first_hilbert_series
        sage: R = singular.ring(0,'(x,y,z)','dp')
        sage: I = singular.ideal(['x^2','y^2','z^2'])
        sage: first_hilbert_series(I)
        -t^6 + 3*t^4 - 3*t^2 + 1
        sage: first_hilbert_series(I.name())
        -t^6 + 3*t^4 - 3*t^2 + 1

    """
    cdef dict AN
    # The "active node". If a recursive computation is needed, it will be equipped
    # with a 'Left' and a 'Right' child node, and some 'Multipliers'. Later, the first Hilbert
    # series of the left child node will be stored in 'LeftFHS', and together with
    # the first Hilbert series of the right child node and the multiplier yields
    # the first Hilbert series of 'Id'.
    cdef tuple w
    if isinstance(I.parent(),Singular):
        S = I._check_valid()
        # First, we need to deal with quotient rings, which also covers the case
        # of graded commutative rings that arise as cohomology rings in odd characteristic.
        # We replace everything by a commutative version of the quotient ring.
        br = S('basering')
        if S.eval('isQuotientRing(basering)')=='1':
            L = S('ringlist(basering)')
            R = S('ring(list(%s[1..3],ideal(0)))'%L.name())
            R.set_ring()
            I = S('fetch(%s,%s)+ideal(%s)'%(br.name(),I.name(),br.name()))

        I = [ETuple([int(x) for x in S.eval('string(leadexp({}[{}]))'.format(I.name(), i)).split(',')]) for i in range(1,int(S.eval('ncols({})'.format(I.name())))+1)]
        br.set_ring()
        if grading is None:
            w = tuple(int(S.eval('deg(var({}))'.format(i))) for i in range(1,int(S.eval('nvars(basering)'))+1))
        else:
            w = tuple(grading)
    else:
        try:
            I = [bla.exponents()[0] for bla in I if bla]
        except TypeError:
            I = [bla.exponents()[0] for bla in I.gens() if bla]
        if grading is not None:
            w = tuple(grading)
        else:
            w = None

    AN = {'Id':interred(I), 'Back':None}

    # Invariant of this function:
    # At each point, fhs will either be NotImplemented or the first Hilbert series of AN.
#~     MaximaleTiefe = 0
#~     Tiefe = 0
    fhs = HilbertBaseCase(AN, w)
    while True:
        if fhs is NotImplemented:
            make_children(AN, w)
            AN = AN['Left']
#~             Tiefe += 1
#~             MaximaleTiefe = max(MaximaleTiefe, Tiefe)
            fhs = HilbertBaseCase(AN, w)
        else:
            if AN['Back'] is None: # We are back on top, i.e., fhs is the First Hilber Series of I
#~                 print 'Maximal depth of recursion:', MaximaleTiefe
                if return_grading:
                    return fhs, w
                else:
                    return fhs
            if AN is AN['Back']['Left']: # We store fhs and proceed to the sibling
                # ... unless there is no sibling
                if AN['Back']['Right'] is None:
                    AN = AN['Back']
                    fhs *= AN['LMult']
                else:
                    AN['Back']['LeftFHS'] = fhs
                    AN = AN['Back']['Right']
                    AN['Back']['Left'] = None
                    fhs = HilbertBaseCase(AN, w)
            else: # FHS of the left sibling is stored, of the right sibling is known.
                AN = AN['Back']
                AN['Right'] = None
#~                 Tiefe -= 1
                fhs = AN['LMult']*AN['LeftFHS'] + AN['RMult']*fhs

def hilbert_poincare_series(I, grading=None):
    r"""
    Return the Hilbert Poincaré series of the given monomial ideal.
    """
    HP,grading = first_hilbert_series(I, grading=grading, return_grading=True)
    # If grading was None, but the ideal lives in Singular, then grading is now
    # the degree vector of Singular's basering.
    # Otherwise, it my still be None.
    if grading is None:
        HS = HP/((1-t)**I.ring().ngens())
    else:
        HS = HP/PR.prod([(1-t**d) for d in grading])
    if HS.denominator().leading_coefficient()<0:
        return (-HS.numerator()/(-HS.denominator()))
    return HS
