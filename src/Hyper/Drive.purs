module Hyper.Drive ( Request(..)
                   , Response(..)
                   , Application
                   , hyperdrive
                   , response
                   , status
                   , header
                   , body
                   ) where

import Prelude
import Control.IxMonad (ibind)
import Data.Bifunctor (class Bifunctor)
import Data.Either (Either)
import Data.HTTP.Method (CustomMethod, Method)
import Data.Newtype (class Newtype)
import Data.Tuple (Tuple(..), curry)
import Foreign.Object as Object
import Foreign.Object (Object)
import Hyper.Conn (Conn)
import Hyper.Header (Header)
import Hyper.Middleware (Middleware, lift')
import Hyper.Middleware.Class (getConn)
import Hyper.Request (class ReadableBody, class Request, getRequestData, readBody)
import Hyper.Response (class Response, class ResponseWritable, ResponseEnded, StatusLineOpen, closeHeaders, end, send, toResponse, writeHeader, writeStatus)
import Hyper.Status (Status, statusOK)

newtype Request body components =
  Request { method :: Either Method CustomMethod
          , url :: String
          , headers :: Object String
          , body :: body
          , components :: components
          }

newtype Response body =
  Response { status :: Status
           , headers :: Object String
           , body :: body
           }

type Application m req res = req -> m res

derive instance newtypeRequest :: Newtype (Request body components) _
derive instance newtypeResponse :: Newtype (Response body) _

derive instance functorRequest :: Functor (Request body)
derive instance functorResponse :: Functor Response

instance bifunctorRequest :: Bifunctor Request where
  bimap l r (Request req) = Request $ req
    { body = l req.body
    , components = r req.components
    }

hyperdrive
  :: forall m req res r components reqBody resBody
   . Monad m
  => Request req m
  => Response res m r
  => ReadableBody req m reqBody
  => ResponseWritable r m resBody
  => Application m (Request reqBody components) (Response resBody)
  -> Middleware
     m
     (Conn req (res StatusLineOpen) components)
     (Conn req (res ResponseEnded) components)
     Unit
hyperdrive app = do
  { method, url, headers } <- getRequestData
  body' <- readBody
  components <- _.components <$> getConn
  let req = Request { method
                    , url
                    , headers
                    , body: body'
                    , components: components
                    }
  Response res <- lift' (app req)
  writeStatus res.status
  Object.foldM (const (curry writeHeader)) unit res.headers
  closeHeaders
  toResponse res.body >>= send
  end
  where
    bind = ibind
    discard = ibind


response
  :: forall body
   .  body
  -> Response body
response b =
  Response
  { status: statusOK
  , headers: Object.empty
  , body: b
  }

status
  :: forall body
   . Status
  -> Response body
  -> Response body
status status' (Response res) =
  Response (res { status = status' })

header
  :: forall body
   . Header
  -> Response body
  -> Response body
header (Tuple k v) (Response res) =
  Response (res { headers = Object.insert k v res.headers })

body
  :: forall a body
   . body
  -> Response a
  -> Response body
body b (Response res) =
  Response (res { body = b })
