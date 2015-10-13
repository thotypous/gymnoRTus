import platform
import numpy as np

if platform.python_implementation() == 'PyPy':

    def where(cond):
        out = []
        for n,c in enumerate(cond):
            if c == True:
                out.append(n)
        return out
    
else:  # not PyPy
    
    def where(cond):
        return np.where(cond)[0]
