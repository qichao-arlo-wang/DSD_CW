#!/usr/bin/env python
# coding: utf-8

# In[5]:


def Find_circuit_vals(R_load):
    # Function to calculate values of circuit
    V_s=15 # Voltage from source
    I_i=50 # Initial current before branching
    I_load=(V_s/(R_load))*1000
    I_2=I_i-I_load
    R_other=V_s/(I_2/1000)
    return I_load,I_2,R_other

print('Values for R_load:')
print('---------------------------------------------------------------------')
print(Find_circuit_vals(350))
print(Find_circuit_vals(400))
print(Find_circuit_vals(500))
print(Find_circuit_vals(1000))
print(Find_circuit_vals(1300))

