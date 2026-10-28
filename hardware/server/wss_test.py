import asyncio
import websockets


async def main() -> None:
    url = "wss://smart-medicine-box.124.156.137.131.nip.io/xiaozhi/v1/"
    async with websockets.connect(url, open_timeout=10) as ws:
        print("WSS OK", ws.state)


asyncio.run(main())
