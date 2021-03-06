{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE RankNTypes            #-}

module Main where

import           Control.Applicative        (empty)
import           Control.Monad              (unless)

import           Data.Time.Units            (Second)
import           GHC.IO.Encoding            (setLocaleEncoding, utf8)
import           Options.Applicative.Simple (simpleOptions)
import           Serokell.Util.Concurrent   (threadDelay)
import           System.Random              (mkStdGen)
import           System.Wlog                (usingLoggerName)

import           Mockable                   (Production (runProduction))

import           Bench.Network.Commons      (MeasureEvent (..), Ping (..), Pong (..),
                                             loadLogConfig, logMeasure)
import qualified Network.Transport.TCP      as TCP
import           Network.Transport.Concrete (concrete)
import           Node                       (Listener (..), NodeAction (..), node,
                                             defaultNodeEnvironment, ConversationActions (..),
                                             simpleNodeEndPoint, noReceiveDelay)
import           Node.Message.Binary        (binaryPacking)
import           ReceiverOptions            (Args (..), argsParser)

main :: IO ()
main = do
    (Args {..}, ()) <-
        simpleOptions
            "bench-receiver"
            "Server utility for benches"
            "Use it!"
            argsParser
            empty

    loadLogConfig logsPrefix logConfig
    setLocaleEncoding utf8

    Right transport_ <- TCP.createTransport (TCP.defaultTCPAddr "127.0.0.1" (show port))
        TCP.defaultTCPParameters
    let transport = concrete transport_

    let prng = mkStdGen 0

    runProduction $ usingLoggerName "receiver" $ do
        node (simpleNodeEndPoint transport) (const noReceiveDelay) (const noReceiveDelay) prng binaryPacking () defaultNodeEnvironment $ \_ ->
            NodeAction (const [pingListener noPong]) $ \_ -> do
                threadDelay (fromIntegral duration :: Second)
  where
    pingListener noPong =
        Listener $ \_ _ cactions -> do
            Just (Ping mid payload) <- recv cactions maxBound
            logMeasure PingReceived mid payload
            unless noPong $ do
                logMeasure PongSent mid payload
                send cactions (Pong mid payload)
