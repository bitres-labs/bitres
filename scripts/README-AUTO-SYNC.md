# Contract Address Auto-Sync Mechanism

## Background

After restarting the Hardhat local node, all contract addresses change and require manual updates to the frontend configuration file `brs-interface/src/config/contracts.ts`. This process is tedious and error-prone.

## Solution

### 1. Auto-Sync Script

**Script Location**: `scripts/sync-contracts-to-interface.js`

**Features**:
- Reads the latest deployed contract addresses from `scripts/main/deployment-local-state.json`
- Automatically generates and updates `brs-interface/src/config/contracts.ts`
- Preserves network configuration, token precision, and other settings

**Manual Usage**:
```bash
cd /home/biostar/work/brs
node scripts/sync-contracts-to-interface.js
```

### 2. Auto-Invocation by Deployment Script

**Modified Content**: `scripts/main/deploy-full-system-local.js`

The deployment script automatically calls the sync script upon completion, no manual operation required.

**Usage**:
```bash
npx hardhat run scripts/main/deploy-full-system-local.js --network localhost
```

After deployment completes, it will automatically:
1. Deploy all contracts
2. Save deployment state to JSON
3. Auto-sync addresses to frontend
4. Vite hot-reloads frontend code

### 3. One-Click Development Environment Restart

**Script Location**: `scripts/restart-local-dev.sh`

**Features**: Complete restart of the entire development environment
- Stop Hardhat node and frontend server
- Start new Hardhat node
- Deploy Bitres system
- Auto-sync contract addresses
- Start frontend server

**Usage**:
```bash
cd /home/biostar/work/brs
./scripts/restart-local-dev.sh
```

Or:
```bash
bash /home/biostar/work/brs/scripts/restart-local-dev.sh
```

## Workflow

### Scenario 1: Hardhat Node Crash/Restart

```bash
# Method 1: Use one-click restart script (recommended)
./scripts/restart-local-dev.sh

# Method 2: Manual steps
npx hardhat node --hostname 0.0.0.0 &  # Start node
npx hardhat run scripts/main/deploy-full-system-local.js --network localhost  # Deploy (will auto-sync)
```

### Scenario 2: Redeployment Only

```bash
# Deployment script will auto-sync addresses
npx hardhat run scripts/main/deploy-full-system-local.js --network localhost
```

### Scenario 3: Modified Contract Code

```bash
# 1. Recompile
npx hardhat compile

# 2. Redeploy (will auto-sync addresses)
npx hardhat run scripts/main/deploy-full-system-local.js --network localhost
```

### Scenario 4: Manual Address Sync (Rarely Needed)

```bash
node scripts/sync-contracts-to-interface.js
```

## File Description

### Key Files

| File Path | Description |
|---------|------|
| `scripts/main/deployment-local-state.json` | Deployment state file (contract address source) |
| `brs-interface/src/config/contracts.ts` | Frontend config file (auto-updated) |
| `scripts/sync-contracts-to-interface.js` | Sync script |
| `scripts/restart-local-dev.sh` | One-click restart script |

### Log Files

| File Path | Description |
|---------|------|
| `/tmp/hardhat-node.log` | Hardhat node log |
| `/tmp/vite-dev.log` | Frontend dev server log |

## Verification

### Check Service Status

```bash
# Hardhat node
lsof -i :8545

# Frontend server
lsof -i :3000

# View logs
tail -f /tmp/hardhat-node.log
tail -f /tmp/vite-dev.log
```

### Check Address Synchronization

```bash
# View deployment state
cat scripts/main/deployment-local-state.json | jq '.contracts'

# View frontend configuration
head -30 /home/biostar/work/brs-interface/src/config/contracts.ts
```

### Access Frontend

- Local: http://localhost:3000
- LAN: http://192.168.2.151:3000
- WSL: http://172.29.182.131:3000

## Important Notes

1. **Auto-sync is only for local development**: Production deployments require manual configuration

2. **Frontend hot reload**: After address sync, Vite will automatically hot-reload all components using the contracts configuration

3. **Data preservation**: The sync script only updates addresses and does not modify network configuration, token precision, or other settings

4. **Path dependency**: The script assumes the following directory structure:
   ```
   /home/biostar/work/
   ├── brs/                  (contracts repository)
   └── brs-interface/        (frontend repository)
   ```

5. **Sync failure does not affect deployment**: If sync fails, deployment still succeeds; you can manually run the sync script

## Troubleshooting

### Issue: Frontend shows "Contract call failed"

**Solution**:
```bash
# Check if addresses are synced
node scripts/sync-contracts-to-interface.js

# Hard refresh browser (Ctrl+Shift+R)
```

### Issue: Sync script cannot find file

**Solution**:
```bash
# Confirm deployment state file exists
ls -l scripts/main/deployment-local-state.json

# Confirm frontend directory exists
ls -l /home/biostar/work/brs-interface/src/config/
```

### Issue: Permission error

**Solution**:
```bash
chmod +x scripts/restart-local-dev.sh
chmod +x scripts/sync-contracts-to-interface.js
```

## Future Optimizations

- [ ] Add contract ABI auto-sync
- [ ] Support multi-network configuration switching
- [ ] Add deployment history logging
- [ ] Add address validation to frontend
