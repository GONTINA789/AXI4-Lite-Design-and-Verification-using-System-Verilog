# 🔷 Design and Verification of AXI4-Lite Interface using SystemVerilog

## 📌 Overview
RTL design and functional verification of an AXI4-Lite Master-Slave interface using a SystemVerilog layered testbench with assertions, directed and random testing, and self-checking scoreboard.

This project demonstrates a complete AXI4-Lite protocol implementation and verification flow used in SoC design.

---

## 🚀 Key Features

### 🔹 Design
- AXI4-Lite Master implemented using FSM
- AXI4-Lite Slave with 256-entry register file
- Supports read and write transactions
- Implements VALID–READY handshake protocol
- Memory-mapped communication

### 🔹 Verification
- Layered SystemVerilog Testbench (UVM-style)
  - Transaction
  - Driver
  - Scoreboard
  - Agent
  - Environment
- Self-checking verification
- Assertion-Based Verification (SVA)

### 🔹 Testing
- Directed testcases:
  - Basic write-read
  - Multi-address access
  - Overwrite scenario
- 10 Random testcases
- Total Reads Verified: 14  
- PASS = 14, FAIL = 0  

---

## 🧠 AXI4-Lite Protocol Summary
- Simplified version of AXI4
- Single master and single slave
- No burst transfers
- Uses 5 channels:
  - Write Address (AW)
  - Write Data (W)
  - Write Response (B)
  - Read Address (AR)
  - Read Data (R)

- Handshake mechanism:

---

## 🏗️ Architecture

### 🔸 DUT
- axi_master.sv
- axi_slave.sv
- dut.sv

### 🔸 Interfaces
- axi_if.sv (Top-level interface)
- in_if.sv (Internal AXI interface)

### 🔸 Testbench Components
- axi_transaction.sv
- axi_driver.sv
- axi_scoreboard.sv
- axi_agent.sv
- axi_environment.sv
- axi_test.sv
- tb.sv

---

## 🔄 Verification Flow

Generator → Driver → DUT → Scoreboard  

- Driver handles both stimulus and read data capture
- Scoreboard compares DUT output with reference model
- Mailboxes used for inter-process communication

---

## 📊 Functional Coverage
- Address coverage (low / mid / high ranges)
- Random address-data combinations
- Ensures full address space is exercised

🎯 Coverage Achieved: 100%

---

## 🧪 Assertions (SVA)
- No simultaneous read and write operations
- No unknown (X/Z) data during read
- Protocol correctness validation

---

